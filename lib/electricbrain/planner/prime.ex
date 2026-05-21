defmodule Electricbrain.Planner.Prime do
  @moduledoc """
  Idempotent priming of planner entries for a given week — used by both
  `PlannerLive.Index` and `Electricbrain.Agenda` so the same recurring
  todo / time-block entries appear whether the user lands on `/plan` or
  on `/` (Today) first.

  For each known TimeBlock availability window and each recurring Todo
  whose `due_in_week?` returns truthy, `week/2` inserts a planner Entry
  if one doesn't already exist for the same `(time_block_id, planned_at)`
  slot or for the same `todo_id` within the target week.

  Idempotency is per-(time_block, planned_at) for time blocks (so multiple
  availability windows on the same block get their own entries) and per
  `todo_id` for recurring todos (so changing the anchor mid-week doesn't
  cascade-duplicate).
  """

  require Ash.Query

  alias Electricbrain.Planner.Entry
  alias Electricbrain.TimeBlocks.Availability, as: TimeBlockAvailability
  alias Electricbrain.TimeBlocks.TimeBlock
  alias Electricbrain.Todos.Recurrence
  alias Electricbrain.Todos.Todo

  @doc """
  Primes the week beginning `week_start` (the user-local Monday). Returns
  `:ok`. Safe to call repeatedly — duplicates are deduped via integer
  microsecond keys (DB-loaded DateTimes have precision `{n, 6}` while
  freshly-computed ones are `{0, 0}`, so naive struct equality misses
  the match).
  """
  @spec week(map(), Date.t()) :: :ok
  def week(user, week_start) do
    existing = read_week_entries(user, week_start)

    existing_time_block_slots =
      MapSet.new(existing, &{&1.time_block_id, datetime_key(&1.planned_at)})

    existing_todo_ids = existing |> Enum.map(& &1.todo_id) |> MapSet.new()

    prime_time_blocks(user, week_start, existing_time_block_slots)
    prime_recurring_todos(user, week_start, existing_todo_ids)

    :ok
  end

  @doc """
  Returns the Monday (in `timezone`) of the week containing `now`.
  """
  @spec monday_in_tz(DateTime.t(), String.t()) :: Date.t()
  def monday_in_tz(now, timezone) do
    local = DateTime.shift_zone!(now, timezone)
    date = DateTime.to_date(local)
    days_back = Date.day_of_week(date) - 1
    Date.add(date, -days_back)
  end

  defp read_week_entries(user, week_start) do
    Entry
    |> Ash.Query.filter(week_start == ^week_start)
    |> Ash.Query.load([:todo, :habit, :time_block])
    |> Ash.read!(actor: user)
  end

  defp datetime_key(nil), do: nil
  defp datetime_key(%DateTime{} = dt), do: DateTime.to_unix(dt, :microsecond)

  defp prime_time_blocks(user, week_start, existing_slots) do
    time_blocks =
      TimeBlock
      |> Ash.Query.load(:availabilities)
      |> Ash.read!(actor: user)

    for block <- time_blocks,
        avail <- block.availabilities,
        dow <- availability_days(avail),
        planned_at = availability_to_utc(week_start, dow, avail.start_time, user.timezone),
        planned_at != nil,
        not MapSet.member?(existing_slots, {block.id, datetime_key(planned_at)}) do
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
  end

  defp prime_recurring_todos(user, week_start, existing_todo_ids) do
    # `status != :done` is intentionally NOT applied here — recurring
    # todos are never "completed" globally; the per-week presence on
    # the planner is the cycle.
    todos =
      Todo
      |> Ash.Query.filter(recurrence != :none)
      |> Ash.read!(actor: user)

    for todo <- todos,
        not MapSet.member?(existing_todo_ids, todo.id),
        {:ok, planned_at} <-
          [Recurrence.due_in_week?(todo, week_start, user.timezone)] do
      Entry
      |> Ash.Changeset.for_create(
        :create,
        %{
          week_start: week_start,
          planned_at: planned_at,
          todo_id: todo.id
        },
        actor: user
      )
      |> Ash.create!()
    end
  end

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
end
