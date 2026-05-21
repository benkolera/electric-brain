defmodule ElectricbrainWeb.HomeLive do
  use ElectricbrainWeb, :live_view

  require Ash.Query
  import ElectricbrainWeb.AgendaHelpers

  alias Electricbrain.Habits.Completion
  alias Electricbrain.Habits.Habit
  alias Electricbrain.Planner.Entry
  alias Electricbrain.TimeBlocks.TimeBlock
  alias Electricbrain.Todos.Todo

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns[:current_user] do
      Electricbrain.Agenda.refresh(socket.assigns.current_user.id)
    end

    {:ok,
     socket
     |> assign(:page_title, "Today")
     |> assign(:new_user?, new_user?(socket.assigns[:current_user]))}
  end

  # A user with no habits and no time blocks hasn't set the app up yet —
  # the home page shows a welcome / next-steps block instead of just
  # "nothing planned today".
  defp new_user?(nil), do: false

  defp new_user?(user) do
    habit_count = Habit |> Ash.read!(actor: user) |> length()
    block_count = TimeBlock |> Ash.read!(actor: user) |> length()
    habit_count == 0 and block_count == 0
  end

  @impl true
  def handle_event("complete_habit", %{"id" => habit_id}, socket) do
    user = socket.assigns.current_user

    Completion
    |> Ash.Changeset.for_create(:create, %{habit_id: habit_id}, actor: user)
    |> Ash.create!()

    Electricbrain.Agenda.refresh(user.id)

    {:noreply, put_flash(socket, :info, "Marked done")}
  end

  def handle_event("toggle_todo", %{"id" => todo_id}, socket) do
    user = socket.assigns.current_user

    Todo
    |> Ash.get!(todo_id, actor: user)
    |> Ash.Changeset.for_update(:toggle, %{}, actor: user)
    |> Ash.update!()

    Electricbrain.Agenda.refresh(user.id)

    {:noreply, socket}
  end

  # For recurring todos we mark the planner Entry done-this-cycle rather
  # than toggling the parent Todo (the parent is "recurring forever").
  def handle_event("complete_entry", %{"id" => entry_id}, socket) do
    user = socket.assigns.current_user

    Entry
    |> Ash.get!(entry_id, actor: user)
    |> Ash.Changeset.for_update(:complete, %{}, actor: user)
    |> Ash.update!()

    Electricbrain.Agenda.refresh(user.id)

    {:noreply, put_flash(socket, :info, "Marked done")}
  end

  defp today_window(tz, now) do
    tz = tz || "Etc/UTC"
    local_now = DateTime.shift_zone!(now, tz)
    today_start_local = DateTime.new!(DateTime.to_date(local_now), ~T[00:00:00], tz)
    tomorrow_start_local = DateTime.add(today_start_local, 24 * 60 * 60, :second)

    {DateTime.shift_zone!(today_start_local, "Etc/UTC"),
     DateTime.shift_zone!(tomorrow_start_local, "Etc/UTC")}
  end

  defp overlaps_today?(item, today_start, tomorrow_start) do
    DateTime.compare(item.entry.planned_at, tomorrow_start) == :lt and
      DateTime.compare(item.end_time, today_start) == :gt
  end

  defp partition(items, now) do
    Enum.reduce(items, {[], [], []}, fn it, {past, current, upcoming} ->
      cond do
        DateTime.compare(it.end_time, now) != :gt ->
          {past ++ [it], current, upcoming}

        DateTime.compare(it.entry.planned_at, now) != :gt ->
          {past, current ++ [it], upcoming}

        true ->
          {past, current, upcoming ++ [it]}
      end
    end)
  end

  defp format_today(timezone) do
    tz = timezone || "Etc/UTC"
    local = DateTime.shift_zone!(DateTime.utc_now(), tz)
    Calendar.strftime(local, "%A, %d %b %Y")
  end

  attr :item, :map, required: true
  attr :kind, :atom, required: true
  attr :timezone, :string, default: nil

  defp day_item(assigns) do
    ~H"""
    <li class={[
      "flex items-center gap-3 p-3 bg-base-200 border border-base-300 rounded-box",
      @kind == :past && "opacity-50",
      @kind == :now && "ring-1 ring-accent"
    ]}>
      <span class="font-mono text-xs text-neutral-content/60 whitespace-nowrap min-w-[6rem]">
        {format_time_range(@item, @timezone)}
      </span>
      <div class="flex-1 min-w-0">
        <p class={["font-medium truncate", @kind == :past && "line-through"]}>
          {item_title(@item)}
        </p>
      </div>
      <%= if @kind == :now do %>
        <span class="inline-flex items-center gap-1 text-xs text-accent font-semibold">
          <span class="size-2 rounded-full bg-accent animate-pulse"></span> Now
        </span>
        <span class="badge badge-ghost badge-sm font-mono">
          {format_hhmm(minutes_remaining(@item))} left
        </span>
      <% else %>
        <span class="badge badge-ghost badge-sm font-mono">
          {format_hhmm(@item.duration_minutes)}
        </span>
      <% end %>
      <.complete_button item={@item} />
    </li>
    """
  end

  attr :item, :map, required: true

  defp complete_button(assigns) do
    habit = assigns.item.entry.habit
    todo = assigns.item.entry.todo

    assigns =
      assigns
      |> assign(:habit, habit)
      |> assign(:todo, todo)
      |> assign(:ritual?, habit && is_list(habit.ritual_steps) && habit.ritual_steps != [])
      |> assign(:recurring_todo?, todo && todo.recurrence in [:weekly, :biweekly, :monthly])

    ~H"""
    <%= cond do %>
      <% @ritual? -> %>
        <.link
          navigate={~p"/habits?ritual=#{@habit.id}"}
          class="btn btn-xs btn-success"
          title="Open ritual"
        >
          <.icon name="hero-list-bullet-micro" class="size-4" />
        </.link>
      <% @habit -> %>
        <button
          type="button"
          phx-click="complete_habit"
          phx-value-id={@habit.id}
          class="btn btn-xs btn-success"
          title="Mark done"
        >
          <.icon name="hero-check-micro" class="size-4" />
        </button>
      <% @recurring_todo? -> %>
        <button
          type="button"
          phx-click="complete_entry"
          phx-value-id={@item.entry.id}
          class="btn btn-xs btn-success"
          title="Done this cycle"
        >
          <.icon name="hero-check-micro" class="size-4" />
        </button>
      <% @todo -> %>
        <button
          type="button"
          phx-click="toggle_todo"
          phx-value-id={@todo.id}
          class={[
            "btn btn-xs",
            (@todo.status == :done && "btn-ghost") || "btn-success"
          ]}
          title={if @todo.status == :done, do: "Unmark", else: "Mark done"}
        >
          <.icon name="hero-check-micro" class="size-4" />
        </button>
      <% true -> %>
        <span></span>
    <% end %>
    """
  end

  @impl true
  def render(assigns) do
    items = (assigns.now_agenda && assigns.now_agenda[:items]) || []
    tz = assigns.current_user.timezone
    now = DateTime.utc_now()

    {today_start, tomorrow_start} = today_window(tz, now)

    items = Enum.filter(items, &overlaps_today?(&1, today_start, tomorrow_start))

    {past, current, upcoming} = partition(items, now)

    assigns =
      assigns
      |> assign(past: past, current: current, upcoming: upcoming, tz: tz)

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} now_agenda={assigns[:now_agenda]}>
      <div>
        <h1 class="font-display text-3xl font-bold tracking-tight text-primary drop-shadow-[0_0_12px_var(--color-primary)]">
          Today
        </h1>
        <p class="text-sm text-neutral-content/70">{format_today(@tz)}</p>
      </div>

      <%= cond do %>
        <% @new_user? -> %>
          <.welcome_block />
        <% @past == [] and @current == [] and @upcoming == [] -> %>
          <div class="text-center py-12 text-neutral-content/60">
            Nothing planned today. <.link navigate={~p"/plan"} class="link link-primary">Plan your week</.link>.
          </div>
        <% true -> %>
          <ul class="space-y-2">
            <%= for item <- @past do %>
              <.day_item item={item} kind={:past} timezone={@tz} />
            <% end %>
            <%= for item <- @current do %>
              <.day_item item={item} kind={:now} timezone={@tz} />
            <% end %>
            <%= for item <- @upcoming do %>
              <.day_item item={item} kind={:upcoming} timezone={@tz} />
            <% end %>
          </ul>
      <% end %>
    </Layouts.app>
    """
  end

  defp welcome_block(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-300">
      <div class="card-body space-y-4">
        <div>
          <h2 class="card-title text-2xl">Welcome to Electric Brain</h2>
          <p class="text-sm text-neutral-content/80 mt-1">
            A second brain built around <em>balance across life areas</em>, not throughput.
            The heart is a Sunday planning ritual: look back, place the week ahead onto
            the calendar, sync to Google, live the plan.
          </p>
        </div>

        <div>
          <p class="text-sm font-semibold mb-2">Get set up — in this order:</p>
          <ol class="space-y-2 list-decimal list-inside text-sm">
            <li>
              <.link navigate={~p"/categories"} class="link link-primary">
                Edit the category tree
              </.link>
              — Health, Work, Hobbies, Relationships. Everything else points at one of these.
            </li>
            <li>
              <.link navigate={~p"/time-blocks"} class="link link-primary">Set time blocks</.link>
              — Sleep, Work, Deep Work. The planner auto-places these from availability windows.
            </li>
            <li>
              <.link navigate={~p"/habits"} class="link link-primary">Add habits</.link>
              — recurring intents with counts ("3× per week"). Identity statements optional.
            </li>
            <li>
              <.link navigate={~p"/plan"} class="link link-primary">Open the planner</.link>
              — drag todos and habits onto the week. Sync to Google when you're happy.
            </li>
            <li>
              <.link navigate={~p"/help"} class="link link-primary">Read the guide</.link>
              — the philosophy and how all the pieces link together.
            </li>
          </ol>
        </div>

        <p class="text-xs text-neutral-content/60">
          This welcome disappears once you've added a habit or a time block.
        </p>
      </div>
    </div>
    """
  end
end
