defmodule Electricbrain.Agenda do
  @moduledoc """
  Per-user GenServer that tracks what's happening *now* and what's *next* from
  the user's PlannerEntries. Wakes only at entry transitions and broadcasts via
  PubSub when current/next changes.

  Subscribers listen on `Electricbrain.Agenda.topic(user_id)` for
  `{:agenda_changed, %{current: [item], next: item | nil}}` messages. An `item`
  is `%{entry: %Entry{}, end_time: DateTime, duration_minutes: integer}`.

  Mutations to the planner should call `Electricbrain.Agenda.broadcast_planner_changed/1`
  (or directly publish on the planner topic) so the running actor refreshes.
  """

  use GenServer

  require Ash.Query

  alias Electricbrain.Planner.Entry

  def child_spec(user_id) do
    %{
      id: {__MODULE__, user_id},
      start: {__MODULE__, :start_link, [user_id]},
      restart: :transient
    }
  end

  def ensure_started(user_id) when is_binary(user_id) do
    case Registry.lookup(Electricbrain.Agenda.Registry, user_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        case DynamicSupervisor.start_child(
               Electricbrain.Agenda.Supervisor,
               {__MODULE__, user_id}
             ) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          err -> err
        end
    end
  end

  def state(user_id) when is_binary(user_id) do
    with {:ok, pid} <- ensure_started(user_id) do
      GenServer.call(pid, :state)
    end
  end

  def refresh(user_id) when is_binary(user_id) do
    case Registry.lookup(Electricbrain.Agenda.Registry, user_id) do
      [] -> :ok
      [{pid, _}] -> GenServer.cast(pid, :refresh)
    end
  end

  def stop(user_id) when is_binary(user_id) do
    case Registry.lookup(Electricbrain.Agenda.Registry, user_id) do
      [] -> :ok
      [{pid, _}] -> DynamicSupervisor.terminate_child(Electricbrain.Agenda.Supervisor, pid)
    end
  end

  @doc """
  Ensures the user's agenda actor is running, subscribes the calling process to
  its updates, and returns the current `%{current:, next:}` snapshot.
  """
  def subscribe(user_id) when is_binary(user_id) do
    with {:ok, _pid} <- ensure_started(user_id),
         :ok <- Phoenix.PubSub.subscribe(Electricbrain.PubSub, topic(user_id)) do
      {:ok, GenServer.call({:via, Registry, {Electricbrain.Agenda.Registry, user_id}}, :state)}
    end
  end

  @doc "PubSub topic that subscribers listen on for {:agenda_changed, ...}."
  def topic(user_id), do: "agenda:#{user_id}"

  @doc "Internal PubSub topic the actor subscribes to for refresh signals."
  def planner_topic(user_id), do: "planner_entries:#{user_id}"

  @doc "Broadcast a planner change so any running agenda for this user refreshes."
  def broadcast_planner_changed(user_id) do
    Phoenix.PubSub.broadcast(
      Electricbrain.PubSub,
      planner_topic(user_id),
      {:planner_entries, :changed}
    )
  end

  def start_link(user_id) do
    GenServer.start_link(__MODULE__, user_id, name: via(user_id))
  end

  defp via(user_id), do: {:via, Registry, {Electricbrain.Agenda.Registry, user_id}}

  @impl true
  def init(user_id) do
    try do
      user = Ash.get!(Electricbrain.Accounts.User, user_id, authorize?: false)
      Phoenix.PubSub.subscribe(Electricbrain.PubSub, planner_topic(user_id))
      state = build_state(user)
      schedule_next_wake(state)
      {:ok, state}
    rescue
      e -> {:stop, {:init_failed, e}}
    end
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, public_state(state), state}
  end

  @impl true
  def handle_cast(:refresh, state) do
    {:noreply, recompute(state)}
  end

  @impl true
  def handle_info(:transition, state), do: {:noreply, recompute(state)}

  def handle_info({:planner_entries, :changed}, state), do: {:noreply, recompute(state)}

  defp recompute(%{user: user} = state) do
    new_state = build_state(user)
    if changed?(state, new_state), do: broadcast(user.id, new_state)
    schedule_next_wake(new_state)
    new_state
  end

  defp build_state(user) do
    now = DateTime.utc_now()
    items = load_items(user, now)
    {current, next} = compute_current_next(items, now)
    %{user: user, items: items, current: current, next: next}
  end

  defp load_items(user, now) do
    {window_start, window_end} = day_window(user, now)

    Entry
    |> Ash.Query.load([:todo, :time_block, habit: :ritual_steps])
    |> Ash.Query.sort(planned_at: :asc)
    |> Ash.read!(actor: user)
    |> Enum.filter(fn e ->
      not is_nil(e.planned_at) and
        DateTime.compare(e.planned_at, window_start) != :lt and
        DateTime.compare(e.planned_at, window_end) == :lt
    end)
    |> Enum.map(&to_item/1)
  end

  defp to_item(entry) do
    duration = resolve_duration(entry)
    end_time = DateTime.add(entry.planned_at, duration * 60, :second)
    %{entry: entry, end_time: end_time, duration_minutes: duration}
  end

  defp resolve_duration(entry) do
    cond do
      is_integer(entry.duration_minutes) ->
        entry.duration_minutes

      entry.habit && is_integer(entry.habit.duration_minutes) ->
        entry.habit.duration_minutes

      entry.todo && is_integer(entry.todo.duration_minutes) ->
        entry.todo.duration_minutes

      entry.time_block && is_integer(entry.time_block.duration_minutes) ->
        entry.time_block.duration_minutes

      true ->
        60
    end
  end

  @doc """
  Given a list of `%{entry:, end_time:, ...}` items and a `now`, returns
  `{current_items, next_item_or_nil}` where current = items overlapping now and
  next = soonest item starting after now.
  """
  def compute_current_next(items, now) do
    current =
      Enum.filter(items, fn it ->
        DateTime.compare(it.entry.planned_at, now) != :gt and
          DateTime.compare(now, it.end_time) == :lt
      end)

    next =
      items
      |> Enum.filter(fn it -> DateTime.compare(it.entry.planned_at, now) == :gt end)
      |> Enum.min_by(& &1.entry.planned_at, DateTime, fn -> nil end)

    {current, next}
  end

  defp day_window(user, now) do
    tz = user.timezone || "Etc/UTC"
    local_now = DateTime.shift_zone!(now, tz)
    today_start_local = DateTime.new!(DateTime.to_date(local_now), ~T[00:00:00], tz)
    start_local = DateTime.add(today_start_local, -24 * 60 * 60, :second)
    end_local = DateTime.add(today_start_local, 2 * 24 * 60 * 60, :second)

    {DateTime.shift_zone!(start_local, "Etc/UTC"), DateTime.shift_zone!(end_local, "Etc/UTC")}
  end

  defp schedule_next_wake(%{items: items}) do
    now = DateTime.utc_now()

    transitions =
      items
      |> Enum.flat_map(fn it -> [it.entry.planned_at, it.end_time] end)
      |> Enum.filter(fn t -> DateTime.compare(t, now) == :gt end)

    case Enum.min(transitions, DateTime, fn -> nil end) do
      nil ->
        :ok

      t ->
        ms = DateTime.diff(t, now, :millisecond) |> max(100)
        Process.send_after(self(), :transition, ms)
    end
  end

  defp broadcast(user_id, state) do
    Phoenix.PubSub.broadcast(
      Electricbrain.PubSub,
      topic(user_id),
      {:agenda_changed, public_state(state)}
    )
  end

  defp public_state(%{current: c, next: n, items: items}),
    do: %{current: c, next: n, items: items}

  defp changed?(%{current: c1, next: n1}, %{current: c2, next: n2}) do
    ids(c1) != ids(c2) or id_of(n1) != id_of(n2)
  end

  defp ids(items), do: items |> Enum.map(& &1.entry.id) |> Enum.sort()
  defp id_of(nil), do: nil
  defp id_of(%{entry: %{id: id}}), do: id
end
