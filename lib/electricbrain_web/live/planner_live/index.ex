defmodule ElectricbrainWeb.PlannerLive.Index do
  use ElectricbrainWeb, :live_view

  require Ash.Query

  alias Electricbrain.Categories
  alias Electricbrain.Categories.Colors
  alias Electricbrain.GoogleCalendar
  alias Electricbrain.Habits.Habit
  alias Electricbrain.TimeBlocks.Availability, as: TimeBlockAvailability
  alias Electricbrain.TimeBlocks.TimeBlock
  alias Electricbrain.Planner.Entry
  alias Electricbrain.Todos.Todo

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    monday = monday_in_tz(DateTime.utc_now(), user.timezone)
    categories = Categories.list_with_paths(user)

    {:ok,
     socket
     |> assign(:page_title, "Plan")
     |> assign(:timezone, user.timezone)
     |> assign(:week_start, monday)
     |> assign(:adding, false)
     |> assign(:armed_id, nil)
     |> assign(:selected_entry_id, nil)
     |> assign(:categories_by_id, Map.new(categories, &{&1.id, &1}))
     |> load_week()}
  end

  defp load_week(socket) do
    user = socket.assigns.current_user
    week_start = socket.assigns.week_start

    entries = read_week_entries(user, week_start)

    entries =
      if entries == [] do
        prime_week(user, week_start)
        read_week_entries(user, week_start)
      else
        entries
      end

    {scheduled, floating} = Enum.split_with(entries, & &1.planned_at)

    candidates = list_candidates(user, entries)
    totals = category_totals(entries, socket.assigns.categories_by_id)

    floating_ids = MapSet.new(floating, & &1.id)
    scheduled_ids = MapSet.new(scheduled, & &1.id)

    armed_id =
      case Map.get(socket.assigns, :armed_id) do
        nil -> nil
        id -> if MapSet.member?(floating_ids, id), do: id, else: nil
      end

    selected_entry_id =
      case Map.get(socket.assigns, :selected_entry_id) do
        nil -> nil
        id -> if MapSet.member?(scheduled_ids, id), do: id, else: nil
      end

    socket
    |> assign(:scheduled, scheduled)
    |> assign(:floating, floating)
    |> assign(:candidates, candidates)
    |> assign(:category_totals, totals)
    |> assign(:armed_id, armed_id)
    |> assign(:selected_entry_id, selected_entry_id)
  end

  # Flat list of `{node, depth, subtree_minutes}` for every category
  # that has planned time (directly or via descendants). Roots first,
  # children indented under their parent via :depth, alphabetical
  # within each sibling group. Used by the planner header's
  # "Planned this week" tree view.
  defp category_totals(entries, categories_by_id) do
    per_cat = direct_minutes_per_category(entries)

    cats_by_parent =
      categories_by_id
      |> Map.values()
      |> Enum.group_by(& &1.parent_id)
      |> Enum.into(%{}, fn {parent_id, kids} ->
        {parent_id, Enum.sort_by(kids, &String.downcase(&1.name))}
      end)

    roots = Map.get(cats_by_parent, nil, [])

    flatten_totals(roots, cats_by_parent, per_cat, categories_by_id, 0, [])
    |> Enum.reverse()
  end

  defp direct_minutes_per_category(entries) do
    Enum.reduce(entries, %{}, fn entry, acc ->
      schedulable = entry_schedulable(entry)
      category_id = schedulable && schedulable.category_id

      if category_id do
        mins = entry_duration_minutes(entry)
        Map.update(acc, category_id, mins, &(&1 + mins))
      else
        acc
      end
    end)
  end

  defp flatten_totals(nodes, cats_by_parent, per_cat, categories_by_id, depth, acc) do
    Enum.reduce(nodes, acc, fn node, acc ->
      subtree = subtree_minutes(node, cats_by_parent, per_cat)

      if subtree == 0 do
        acc
      else
        color_id = Colors.resolve_id(categories_by_id, node.id)

        row = %{
          id: node.id,
          name: node.name,
          minutes: subtree,
          depth: depth,
          color_hex: Colors.hex_for(color_id)
        }

        children = Map.get(cats_by_parent, node.id, [])

        flatten_totals(
          children,
          cats_by_parent,
          per_cat,
          categories_by_id,
          depth + 1,
          [row | acc]
        )
      end
    end)
  end

  defp subtree_minutes(node, cats_by_parent, per_cat) do
    self_mins = Map.get(per_cat, node.id, 0)
    children = Map.get(cats_by_parent, node.id, [])

    self_mins +
      Enum.sum(Enum.map(children, &subtree_minutes(&1, cats_by_parent, per_cat)))
  end

  defp format_minutes(0), do: "0m"

  defp format_minutes(minutes) do
    hours = div(minutes, 60)
    mins = rem(minutes, 60)

    cond do
      hours == 0 -> "#{mins}m"
      mins == 0 -> "#{hours}h"
      true -> "#{hours}h #{mins}m"
    end
  end

  defp list_candidates(user, entries) do
    pinned_todo_ids =
      entries
      |> Enum.map(& &1.todo_id)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    todos =
      Todo
      |> Ash.Query.filter(status != :done)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read!(actor: user)
      |> Enum.reject(&MapSet.member?(pinned_todo_ids, &1.id))
      |> Enum.map(&Map.put(&1, :kind, :todo))

    habits =
      Habit
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read!(actor: user)
      |> Enum.map(&Map.put(&1, :kind, :habit))

    todos ++ habits
  end

  defp read_week_entries(user, week_start) do
    Entry
    |> Ash.Query.filter(week_start == ^week_start)
    |> Ash.Query.load([:todo, :habit, :time_block])
    |> Ash.read!(actor: user)
  end

  defp prime_week(user, week_start) do
    time_blocks =
      TimeBlock
      |> Ash.Query.load(:availabilities)
      |> Ash.read!(actor: user)

    for block <- time_blocks,
        avail <- block.availabilities,
        dow <- availability_days(avail),
        planned_at = availability_to_utc(week_start, dow, avail.start_time, user.timezone),
        planned_at != nil do
      Entry
      |> Ash.Changeset.for_create(
        :create,
        %{
          week_start: week_start,
          planned_at: planned_at,
          duration_minutes: TimeBlockAvailability.duration_minutes(avail),
          time_block_id: block.id
        },
        actor: user
      )
      |> Ash.create!()
    end

    :ok
  end

  # nil day_of_week means "every day" — expand into 1..7.
  defp availability_days(%{day_of_week: nil}), do: 1..7 |> Enum.to_list()
  defp availability_days(%{day_of_week: dow}), do: [dow]

  defp availability_to_utc(week_start, dow, start_time, timezone) do
    date = Date.add(week_start, dow - 1)

    case DateTime.new(date, start_time, timezone) do
      {:ok, dt} -> DateTime.shift_zone!(dt, "Etc/UTC")
      {:ambiguous, _earlier, later} -> DateTime.shift_zone!(later, "Etc/UTC")
      {:gap, _before, after_gap} -> DateTime.shift_zone!(after_gap, "Etc/UTC")
      {:error, _} -> nil
    end
  end

  defp monday_in_tz(now, timezone) do
    local = DateTime.shift_zone!(now, timezone)
    date = DateTime.to_date(local)
    days_back = Date.day_of_week(date) - 1
    Date.add(date, -days_back)
  end

  defp event_payload(entries, timezone, categories_by_id) do
    Enum.flat_map(entries, fn entry ->
      start_utc = entry.planned_at
      duration = entry_duration_minutes(entry) * 60
      end_utc = DateTime.add(start_utc, duration, :second)
      title = entry_title(entry)
      color_id = entry_color_id(entry, categories_by_id)
      calendar_id = Colors.name_for(color_id) |> String.downcase()

      entry
      |> event_slices(start_utc, end_utc, timezone)
      |> Enum.with_index(fn {s_utc, e_utc}, idx ->
        base =
          %{
            id: "#{entry.id}__chunk__#{idx}",
            title: title || "(untitled)",
            start: DateTime.to_iso8601(s_utc),
            end: DateTime.to_iso8601(e_utc),
            calendarId: calendar_id,
            _customContent: %{}
          }
          |> Map.put(:_kind, kind_label(entry))

        if idx == 0,
          do: base,
          else: Map.put(base, :_options, %{disableDND: true, disableResize: true})
      end)
    end)
  end

  defp entry_color_id(entry, categories_by_id) do
    schedulable = entry_schedulable(entry)
    category_id = schedulable && schedulable.category_id
    Colors.resolve_id(categories_by_id, category_id)
  end

  defp entry_schedulable(entry) do
    entry.todo || entry.habit || entry.time_block
  end

  # Returns [{start_utc, end_utc}] split at midnight in the user's timezone so
  # Schedule-X renders each day-slice in its time-grid column instead of as a
  # multi-day all-day banner. Capped at two slices — anything longer than 2
  # local days would be unusual for a sleep/ritual block.
  defp event_slices(_entry, start_utc, end_utc, timezone) do
    start_local = DateTime.shift_zone!(start_utc, timezone)
    end_local = DateTime.shift_zone!(end_utc, timezone)
    start_date = DateTime.to_date(start_local)
    end_date = DateTime.to_date(end_local)

    if Date.compare(start_date, end_date) == :eq do
      [{start_utc, end_utc}]
    else
      # Schedule-X's week range-end clamps to 23:59 (minute precision) on the
      # last visible day; an end of 23:59:59 falls outside the range and the
      # slice gets dropped. Use 23:59:00 so the very last visible day's slice
      # still positions in the time grid.
      day1_end_utc =
        start_date
        |> DateTime.new!(~T[23:59:00], timezone)
        |> DateTime.shift_zone!("Etc/UTC")

      day2_start_utc =
        end_date
        |> DateTime.new!(~T[00:00:00], timezone)
        |> DateTime.shift_zone!("Etc/UTC")

      [{start_utc, day1_end_utc}, {day2_start_utc, end_utc}]
    end
  end

  defp kind_label(%{todo_id: tid}) when not is_nil(tid), do: "todo"
  defp kind_label(%{habit_id: hid}) when not is_nil(hid), do: "habit"
  defp kind_label(%{time_block_id: tbid}) when not is_nil(tbid), do: "time_block"

  defp candidate_kind(%{kind: :todo}), do: :todo
  defp candidate_kind(%{kind: :habit}), do: :habit

  defp candidate_label(%{kind: :todo, title: t}), do: t
  defp candidate_label(%{kind: :habit, title: t}), do: t

  defp entry_title(entry) do
    cond do
      entry.todo -> entry.todo.title
      entry.habit -> entry.habit.title
      entry.time_block -> entry.time_block.title
      true -> "(untitled)"
    end
  end

  # Time-block entries hide from the floating-pool sidebar (they're
  # auto-primed onto the calendar from availability windows; the user
  # doesn't drag them around). Kept the function name so callers don't
  # need updating; "fixed schedule" still names the concept correctly.
  defp fixed_schedule_entry?(%{time_block_id: tbid}) when not is_nil(tbid), do: true
  defp fixed_schedule_entry?(_), do: false

  defp selected_entry(_scheduled, nil), do: nil
  defp selected_entry(scheduled, id), do: Enum.find(scheduled, &(&1.id == id))

  defp entry_duration_minutes(entry) do
    schedulable = entry_schedulable(entry)
    entry.duration_minutes || (schedulable && schedulable.duration_minutes) || 60
  end

  # Returns a 0-or-1 element list for the armed entry's habit. Time
  # blocks live on a separate id (entry.time_block_id) so they never
  # reach the floating pool; this only needs to handle todo vs habit
  # entries. The list shape lets the template use `<%= for %>` for
  # clean conditional rendering without nested cases.
  defp armed_habit_for(nil, _entries), do: []

  defp armed_habit_for(armed_id, entries) do
    case Enum.find(entries, &(&1.id == armed_id)) do
      %{habit: %{} = habit} -> [habit]
      _ -> []
    end
  end

  defp format_entry_time_range(entry, timezone) do
    start_local = DateTime.shift_zone!(entry.planned_at, timezone)
    end_local = DateTime.add(start_local, entry_duration_minutes(entry) * 60, :second)

    date = Calendar.strftime(start_local, "%a, %b %-d")
    start_str = Calendar.strftime(start_local, "%-I:%M %p")
    end_str = Calendar.strftime(end_local, "%-I:%M %p")
    "#{date} · #{start_str} – #{end_str}"
  end

  defp format_week_range(monday, timezone) do
    sunday = Date.add(monday, 6)

    "#{Calendar.strftime(monday, "%b %-d")} – #{Calendar.strftime(sunday, "%b %-d")} (#{timezone})"
  end

  @impl true
  def handle_event("prev_week", _params, socket) do
    week_start = Date.add(socket.assigns.week_start, -7)

    {:noreply,
     socket
     |> assign(:week_start, week_start)
     |> load_week()
     |> push_event("planner:set_date", %{date: Date.to_iso8601(week_start)})
     |> push_scheduled_events()}
  end

  def handle_event("next_week", _params, socket) do
    week_start = Date.add(socket.assigns.week_start, 7)

    {:noreply,
     socket
     |> assign(:week_start, week_start)
     |> load_week()
     |> push_event("planner:set_date", %{date: Date.to_iso8601(week_start)})
     |> push_scheduled_events()}
  end

  def handle_event("toggle_adding", _params, socket) do
    {:noreply, assign(socket, :adding, !socket.assigns.adding)}
  end

  def handle_event("add_to_week", %{"kind" => kind, "id" => id}, socket) do
    user = socket.assigns.current_user

    attrs =
      case kind do
        "todo" -> %{todo_id: id, week_start: socket.assigns.week_start, duration_minutes: 60}
        "habit" -> %{habit_id: id, week_start: socket.assigns.week_start, duration_minutes: 60}
      end

    case Entry
         |> Ash.Changeset.for_create(:create, attrs, actor: user)
         |> Ash.create() do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> assign(:adding, false)
         |> load_week()
         |> push_scheduled_events()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add to week")}
    end
  end

  def handle_event("arm_floating", %{"id" => id}, socket) do
    armed = if socket.assigns.armed_id == id, do: nil, else: id
    {:noreply, assign(socket, :armed_id, armed)}
  end

  def handle_event("slot_clicked", _params, %{assigns: %{armed_id: nil}} = socket) do
    {:noreply,
     put_flash(socket, :info, "Click a pool item first, then click a slot to place it.")}
  end

  def handle_event("slot_clicked", %{"instant" => iso}, socket) do
    user = socket.assigns.current_user
    id = socket.assigns.armed_id

    case parse_zoned(iso) do
      {:ok, utc} ->
        Entry
        |> Ash.get!(id, actor: user)
        |> Ash.Changeset.for_update(:schedule, %{planned_at: utc}, actor: user)
        |> Ash.update!()

        {:noreply,
         socket
         |> assign(:armed_id, nil)
         |> load_week()
         |> push_scheduled_events()}

      :error ->
        {:noreply, put_flash(socket, :error, "Invalid date/time")}
    end
  end

  def handle_event("reset_week", _params, socket) do
    user = socket.assigns.current_user
    week_start = socket.assigns.week_start

    entries =
      Entry
      |> Ash.Query.filter(week_start == ^week_start)
      |> Ash.read!(actor: user)

    for entry <- entries do
      delete_from_google_if_synced(user, entry)
      Ash.destroy!(entry, actor: user)
    end

    {:noreply, socket |> load_week() |> push_scheduled_events()}
  end

  def handle_event("unschedule_entry", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    entry = Ash.get!(Entry, id, actor: user)
    delete_from_google_if_synced(user, entry)

    entry
    |> Ash.Changeset.for_update(:unschedule, %{}, actor: user)
    |> Ash.update!()

    {:noreply, socket |> load_week() |> push_scheduled_events()}
  end

  def handle_event("remove_entry", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    entry = Ash.get!(Entry, id, actor: user)
    delete_from_google_if_synced(user, entry)
    Ash.destroy!(entry, actor: user)

    {:noreply, socket |> load_week() |> push_scheduled_events()}
  end

  def handle_event("entry_rescheduled", %{"id" => id, "start" => start_iso} = params, socket) do
    user = socket.assigns.current_user

    with {:ok, start_utc} <- parse_zoned(start_iso) do
      attrs =
        case params["end"] do
          end_iso when is_binary(end_iso) ->
            case parse_zoned(end_iso) do
              {:ok, end_utc} ->
                duration = div(DateTime.diff(end_utc, start_utc, :second), 60)
                %{planned_at: start_utc, duration_minutes: max(duration, 15)}

              _ ->
                %{planned_at: start_utc}
            end

          _ ->
            %{planned_at: start_utc}
        end

      Entry
      |> Ash.get!(id, actor: user)
      |> Ash.Changeset.for_update(:schedule, attrs, actor: user)
      |> Ash.update!()

      {:noreply, socket |> load_week() |> push_scheduled_events()}
    else
      :error -> {:noreply, socket}
    end
  end

  def handle_event(
        "update_entry_time",
        %{"entry_id" => id, "start_time" => start_time, "duration_minutes" => duration_str},
        socket
      ) do
    user = socket.assigns.current_user
    tz = socket.assigns.timezone
    entry = Ash.get!(Entry, id, actor: user)

    with {:ok, start_utc} <- local_date_with_time(entry.planned_at, start_time, tz),
         {duration, ""} <- Integer.parse(duration_str || "") do
      entry
      |> Ash.Changeset.for_update(
        :schedule,
        %{planned_at: start_utc, duration_minutes: max(duration, 5)},
        actor: user
      )
      |> Ash.update!()

      {:noreply, socket |> load_week() |> push_scheduled_events()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Invalid time or duration")}
    end
  end

  def handle_event("entry_clicked", %{"id" => id}, socket) do
    selected = if socket.assigns.selected_entry_id == id, do: nil, else: id
    {:noreply, assign(socket, :selected_entry_id, selected)}
  end

  def handle_event("deselect_entry", _params, socket) do
    {:noreply, assign(socket, :selected_entry_id, nil)}
  end

  def handle_event("sync_to_google", _params, socket) do
    user = socket.assigns.current_user

    if GoogleCalendar.connected?(user) do
      {synced, failed} =
        sync_scheduled_to_google(
          user,
          socket.assigns.scheduled,
          socket.assigns.categories_by_id
        )

      flash_msg =
        cond do
          failed == 0 -> "Synced #{synced} event(s) to Google Calendar"
          synced == 0 -> "Failed to sync #{failed} event(s)"
          true -> "Synced #{synced}, failed #{failed}"
        end

      {:noreply,
       socket
       |> load_week()
       |> put_flash(if(failed == 0, do: :info, else: :error), flash_msg)}
    else
      {:noreply, put_flash(socket, :error, "Connect Google Calendar in Settings first")}
    end
  end

  # Before destroying or unscheduling an entry, drop its Google Calendar
  # event so we don't leave orphans (which then duplicate on the next
  # sync, since the freshly-created entry has google_event_id=nil and
  # the push code POSTs rather than PUTs). delete_event is idempotent —
  # 404/410 are treated as success — so racing or already-deleted events
  # don't error. Failures are logged but don't block the local destroy
  # (Google can be cleaned up later via Calendar.Cleanup.delete_orphans_for_week).
  defp delete_from_google_if_synced(user, entry) do
    if entry.google_event_id && GoogleCalendar.connected?(user) do
      case GoogleCalendar.delete_event(user, entry) do
        :ok ->
          :ok

        {:error, reason} ->
          require Logger

          Logger.warning(
            "Failed to delete Google event for entry #{entry.id}: #{inspect(reason)}"
          )

          :ok
      end
    else
      :ok
    end
  end

  defp sync_scheduled_to_google(user, scheduled, categories_by_id) do
    Enum.reduce(scheduled, {0, 0}, fn entry, {synced, failed} ->
      color_id = entry_color_id(entry, categories_by_id)

      case GoogleCalendar.push_event(user, entry, color_id: color_id) do
        {:ok, google_id} ->
          if entry.google_event_id != google_id do
            entry
            |> Ash.Changeset.for_update(
              :set_google_event_id,
              %{google_event_id: google_id},
              actor: user
            )
            |> Ash.update!()
          end

          {synced + 1, failed}

        {:error, reason} ->
          require Logger
          Logger.warning("Google sync failed for entry #{entry.id}: #{inspect(reason)}")
          {synced, failed + 1}
      end
    end)
  end

  defp push_scheduled_events(socket) do
    payload =
      event_payload(
        socket.assigns.scheduled,
        socket.assigns.timezone,
        socket.assigns.categories_by_id
      )

    push_event(socket, "planner:events", %{events: payload})
  end

  defp parse_zoned(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _offset} -> {:ok, DateTime.shift_zone!(dt, "Etc/UTC")}
      _ -> :error
    end
  end

  defp entry_start_time_local(entry, tz) do
    entry.planned_at
    |> DateTime.shift_zone!(tz)
    |> Calendar.strftime("%H:%M")
  end

  # Keep the entry's existing local date and replace the time component
  # with the user's `HH:MM` input, then shift back to UTC.
  defp local_date_with_time(planned_at_utc, time_str, tz)
       when is_binary(time_str) and not is_nil(planned_at_utc) do
    date =
      planned_at_utc
      |> DateTime.shift_zone!(tz)
      |> DateTime.to_date()

    with [h, m | _] <- String.split(time_str, ":"),
         {hour, ""} <- Integer.parse(h),
         {minute, ""} <- Integer.parse(m),
         {:ok, time} <- Time.new(hour, minute, 0),
         {:ok, local_dt} <- DateTime.new(date, time, tz) do
      {:ok, DateTime.shift_zone!(local_dt, "Etc/UTC")}
    else
      _ -> :error
    end
  end

  defp local_date_with_time(_, _, _), do: :error

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} now_agenda={assigns[:now_agenda]} wide>
      <div class="flex items-center justify-between">
        <div>
          <h1 class="font-display text-3xl font-bold tracking-tight text-accent drop-shadow-[0_0_12px_var(--color-accent)]">
            Plan
          </h1>
          <p class="text-sm text-neutral-content/70">
            {format_week_range(@week_start, @timezone)}
          </p>
        </div>
        <div class="flex items-center gap-2">
          <%= if GoogleCalendar.connected?(@current_user) and @scheduled != [] do %>
            <button
              type="button"
              phx-click="sync_to_google"
              class="btn btn-sm btn-primary"
              title={"Push this week's scheduled events to " <> @current_user.google_email}
            >
              <.icon name="hero-cloud-arrow-up-micro" class="size-4" /> Sync to Google
            </button>
          <% end %>
          <.link navigate={~p"/plan/review"} class="btn btn-sm btn-ghost">
            <.icon name="hero-clipboard-document-check-micro" class="size-4" /> Review
          </.link>
          <button
            type="button"
            phx-click="reset_week"
            data-confirm="Wipe every entry from this week and re-prime from time blocks?"
            class="btn btn-sm btn-ghost text-error"
            title="Delete all entries for this week and re-prime from time blocks"
          >
            <.icon name="hero-arrow-path-micro" class="size-4" /> Reset week
          </button>
          <button type="button" phx-click="prev_week" class="btn btn-sm btn-ghost">
            <.icon name="hero-chevron-left-micro" class="size-4" /> Prev
          </button>
          <button type="button" phx-click="next_week" class="btn btn-sm btn-ghost">
            Next <.icon name="hero-chevron-right-micro" class="size-4" />
          </button>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-[20rem_1fr_20rem] gap-4">
        <aside class="space-y-3">
          <div class="card bg-base-200 border border-base-300">
            <div class="card-body p-4">
              <div class="flex items-center justify-between">
                <h2 class="card-title text-base">This week pool</h2>
                <button
                  type="button"
                  phx-click="toggle_adding"
                  class="btn btn-xs btn-primary"
                >
                  <.icon name="hero-plus-micro" class="size-3.5" /> Add
                </button>
              </div>

              <%= if @armed_id do %>
                <p class="text-xs text-accent mt-1">
                  Click a calendar slot to place this item. Click it again to cancel.
                </p>
                <%= for habit <- armed_habit_for(@armed_id, @floating) do %>
                  <%= if habit.identity_statement do %>
                    <p class="text-xs text-neutral-content/70 mt-1 italic">
                      Doing this means you are: {habit.identity_statement}
                    </p>
                  <% end %>
                  <%= if habit.minimum_viable_action do %>
                    <p class="text-xs text-neutral-content/70 mt-1">
                      <span class="font-medium text-accent">Two-minute fallback:</span>
                      {habit.minimum_viable_action}
                    </p>
                  <% end %>
                <% end %>
              <% end %>

              <ul class="space-y-1.5 mt-2">
                <%= for entry <- @floating do %>
                  <li class={[
                    "flex items-center gap-1 p-2 bg-base-100 rounded border transition-colors",
                    if(@armed_id == entry.id,
                      do: "border-accent ring-2 ring-accent/60",
                      else: "border-base-300 hover:border-accent/60"
                    )
                  ]}>
                    <button
                      type="button"
                      phx-click="arm_floating"
                      phx-value-id={entry.id}
                      class="flex-1 text-left text-sm font-medium truncate cursor-pointer"
                    >
                      {entry_title(entry)}
                    </button>
                    <button
                      type="button"
                      phx-click="remove_entry"
                      phx-value-id={entry.id}
                      data-confirm="Remove from this week?"
                      class="btn btn-xs btn-ghost text-error"
                    >
                      <.icon name="hero-x-mark-micro" class="size-3.5" />
                    </button>
                  </li>
                <% end %>
                <%= if @floating == [] do %>
                  <li class="text-xs text-neutral-content/60 py-2">
                    No floating items. Schedule things by clicking "+ Add".
                  </li>
                <% end %>
              </ul>
            </div>
          </div>

          <%= if @adding do %>
            <div class="card bg-base-200 border border-base-300">
              <div class="card-body p-4">
                <h2 class="card-title text-base">Pick something to plan</h2>
                <ul class="space-y-1 max-h-96 overflow-auto mt-1">
                  <%= for c <- @candidates do %>
                    <li>
                      <button
                        type="button"
                        phx-click="add_to_week"
                        phx-value-kind={candidate_kind(c)}
                        phx-value-id={c.id}
                        class="w-full text-left p-2 hover:bg-base-300/40 rounded flex items-center gap-2"
                      >
                        <span class="badge badge-outline badge-xs">{candidate_kind(c)}</span>
                        <span class="truncate">{candidate_label(c)}</span>
                      </button>
                    </li>
                  <% end %>
                  <%= if @candidates == [] do %>
                    <li class="text-xs text-neutral-content/60 py-2">
                      Nothing to add — create todos or habits first.
                    </li>
                  <% end %>
                </ul>
              </div>
            </div>
          <% end %>

          <%= if selected = selected_entry(@scheduled, @selected_entry_id) do %>
            <div class="card bg-base-200 border-2 border-accent">
              <div class="card-body p-4">
                <div class="flex items-start justify-between gap-2">
                  <div class="flex items-center gap-2">
                    <span class="badge badge-outline badge-xs">{kind_label(selected)}</span>
                    <h2 class="card-title text-base">{entry_title(selected)}</h2>
                  </div>
                  <button
                    type="button"
                    phx-click="deselect_entry"
                    class="btn btn-xs btn-ghost"
                    title="Close"
                  >
                    <.icon name="hero-x-mark-micro" class="size-3.5" />
                  </button>
                </div>
                <p class="text-sm text-neutral-content/80 mt-1">
                  {format_entry_time_range(selected, @timezone)}
                </p>
                <p class="text-xs text-neutral-content/60">
                  {format_minutes(entry_duration_minutes(selected))}
                </p>
                <form
                  phx-submit="update_entry_time"
                  class="mt-2 flex flex-wrap items-center gap-1.5"
                >
                  <input type="hidden" name="entry_id" value={selected.id} />
                  <input
                    type="time"
                    name="start_time"
                    value={entry_start_time_local(selected, @timezone)}
                    step="60"
                    required
                    class="input input-xs input-bordered bg-base-100 font-mono"
                    title="Start time (local)"
                  />
                  <input
                    type="number"
                    name="duration_minutes"
                    value={entry_duration_minutes(selected)}
                    min="5"
                    step="5"
                    required
                    class="input input-xs input-bordered bg-base-100 w-20"
                    title="Duration in minutes"
                  />
                  <span class="text-xs text-neutral-content/60">min</span>
                  <button type="submit" class="btn btn-xs btn-primary">Apply</button>
                </form>
                <div class="flex gap-1 mt-2">
                  <button
                    type="button"
                    phx-click="unschedule_entry"
                    phx-value-id={selected.id}
                    class="btn btn-xs btn-ghost"
                  >
                    <.icon name="hero-arrow-uturn-left-micro" class="size-3.5" /> Unschedule
                  </button>
                  <button
                    type="button"
                    phx-click="remove_entry"
                    phx-value-id={selected.id}
                    data-confirm="Remove from this week?"
                    class="btn btn-xs btn-ghost text-error"
                  >
                    <.icon name="hero-x-mark-micro" class="size-3.5" /> Remove
                  </button>
                </div>
              </div>
            </div>
          <% end %>

          <% sidebar_scheduled = Enum.reject(@scheduled, &fixed_schedule_entry?/1) %>
          <%= if sidebar_scheduled != [] do %>
            <div class="card bg-base-200 border border-base-300">
              <div class="card-body p-4">
                <h2 class="card-title text-base">Scheduled</h2>
                <ul class="space-y-1 mt-2">
                  <%= for entry <- sidebar_scheduled do %>
                    <li class={[
                      "flex items-center gap-2 text-sm rounded px-1 transition-colors",
                      if(@selected_entry_id == entry.id, do: "bg-accent/10", else: "")
                    ]}>
                      <button
                        type="button"
                        phx-click="entry_clicked"
                        phx-value-id={entry.id}
                        class="flex-1 text-left truncate cursor-pointer"
                      >
                        {entry_title(entry)}
                      </button>
                      <button
                        type="button"
                        phx-click="unschedule_entry"
                        phx-value-id={entry.id}
                        class="btn btn-xs btn-ghost"
                        title="Unschedule"
                      >
                        <.icon name="hero-arrow-uturn-left-micro" class="size-3.5" />
                      </button>
                      <button
                        type="button"
                        phx-click="remove_entry"
                        phx-value-id={entry.id}
                        data-confirm="Remove from this week?"
                        class="btn btn-xs btn-ghost text-error"
                      >
                        <.icon name="hero-x-mark-micro" class="size-3.5" />
                      </button>
                    </li>
                  <% end %>
                </ul>
              </div>
            </div>
          <% end %>
        </aside>

        <div class="card bg-base-200 border border-base-300">
          <div class="card-body p-2">
            <div
              id="planner-calendar"
              phx-hook="PlannerCalendar"
              phx-update="ignore"
              data-timezone={@timezone}
              data-week-start={Date.to_iso8601(@week_start)}
              data-events={Jason.encode!(event_payload(@scheduled, @timezone, @categories_by_id))}
              class="bg-base-100 rounded-box"
            >
            </div>
          </div>
        </div>

        <aside class="space-y-3">
          <div class="card bg-base-200 border border-base-300">
            <div class="card-body p-4">
              <h2 class="card-title text-base">Planned this week</h2>

              <%= if @category_totals == [] do %>
                <p class="text-sm text-neutral-content/60 mt-1">
                  Nothing scheduled yet.
                </p>
              <% else %>
                <ul class="text-sm mt-1">
                  <%= for total <- @category_totals do %>
                    <li
                      class="flex items-center gap-2 py-0.5"
                      style={"padding-left: #{total.depth * 1.25}rem"}
                    >
                      <span
                        class="size-2.5 rounded-full border border-neutral-content/30 shrink-0"
                        style={"background:#{total.color_hex}"}
                      >
                      </span>
                      <span class={[
                        "truncate flex-1",
                        total.depth == 0 && "font-medium",
                        total.depth > 0 && "text-neutral-content/80"
                      ]}>
                        {total.name}
                      </span>
                      <span class="text-neutral-content/60 tabular-nums shrink-0">
                        {format_minutes(total.minutes)}
                      </span>
                    </li>
                  <% end %>
                </ul>
              <% end %>
            </div>
          </div>
        </aside>
      </div>
    </Layouts.app>
    """
  end
end
