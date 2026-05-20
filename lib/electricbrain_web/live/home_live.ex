defmodule ElectricbrainWeb.HomeLive do
  use ElectricbrainWeb, :live_view

  alias Electricbrain.Habits.Completion
  alias Electricbrain.Todos.Todo

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns[:current_user] do
      Electricbrain.Agenda.refresh(socket.assigns.current_user.id)
    end

    {:ok, assign(socket, :page_title, "Today")}
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

  defp item_title(%{entry: %{habit: %{title: t}}}) when is_binary(t), do: t
  defp item_title(%{entry: %{todo: %{title: t}}}) when is_binary(t), do: t
  defp item_title(_), do: "Scheduled"

  defp format_time_range(item, tz) do
    tz = tz || "Etc/UTC"
    start_local = DateTime.shift_zone!(item.entry.planned_at, tz)
    end_local = DateTime.shift_zone!(item.end_time, tz)

    if DateTime.to_date(start_local) == DateTime.to_date(end_local) do
      "#{Calendar.strftime(start_local, "%H:%M")}–#{Calendar.strftime(end_local, "%H:%M")}"
    else
      "#{Calendar.strftime(start_local, "%a %H:%M")} – #{Calendar.strftime(end_local, "%a %H:%M")}"
    end
  end

  defp format_hhmm(minutes) when is_integer(minutes) and minutes >= 0 do
    h = div(minutes, 60)
    m = rem(minutes, 60)
    :io_lib.format("~2..0B:~2..0B", [h, m]) |> IO.iodata_to_binary()
  end

  defp minutes_remaining(%{end_time: end_time}) do
    diff = DateTime.diff(end_time, DateTime.utc_now(), :second)
    max(div(diff, 60), 0)
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

    ~H"""
    <%= cond do %>
      <% @ritual? -> %>
        <.link navigate={~p"/habits?ritual=#{@habit.id}"} class="btn btn-xs btn-success" title="Open ritual">
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
      <% @todo -> %>
        <button
          type="button"
          phx-click="toggle_todo"
          phx-value-id={@todo.id}
          class={[
            "btn btn-xs",
            @todo.status == :done && "btn-ghost" || "btn-success"
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

      <%= if @past == [] and @current == [] and @upcoming == [] do %>
        <div class="text-center py-12 text-neutral-content/60">
          Nothing planned today.
          <.link navigate={~p"/plan"} class="link link-primary">Plan your week</.link>.
        </div>
      <% else %>
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
end
