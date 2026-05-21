defmodule Electricbrain.AgendaTest do
  use Electricbrain.DataCase

  alias Electricbrain.Agenda
  alias Electricbrain.Categories
  alias Electricbrain.Habits.Habit
  alias Electricbrain.Planner.Entry
  alias Electricbrain.Todos.Todo

  describe "compute_current_next/2" do
    test "current = items overlapping now; next = soonest after now" do
      now = ~U[2026-05-19 12:00:00Z]

      items = [
        item("a", ~U[2026-05-19 09:00:00Z], 60),
        item("b", ~U[2026-05-19 11:30:00Z], 60),
        item("c", ~U[2026-05-19 13:00:00Z], 60),
        item("d", ~U[2026-05-19 15:00:00Z], 30)
      ]

      {current, next} = Agenda.compute_current_next(items, now)

      assert Enum.map(current, & &1.entry.id) == ["b"]
      assert next.entry.id == "c"
    end

    test "current can stack on overlapping items" do
      now = ~U[2026-05-19 12:00:00Z]

      items = [
        item("a", ~U[2026-05-19 11:30:00Z], 60),
        item("b", ~U[2026-05-19 11:45:00Z], 30)
      ]

      {current, _next} = Agenda.compute_current_next(items, now)
      assert Enum.map(current, & &1.entry.id) |> Enum.sort() == ["a", "b"]
    end

    test "no current, no next when items are all in the past" do
      now = ~U[2026-05-19 20:00:00Z]
      items = [item("a", ~U[2026-05-19 09:00:00Z], 60)]
      assert {[], nil} = Agenda.compute_current_next(items, now)
    end

    test "end is exclusive: an item ending exactly at now is not current" do
      now = ~U[2026-05-19 12:00:00Z]
      items = [item("a", ~U[2026-05-19 11:00:00Z], 60)]
      assert {[], nil} = Agenda.compute_current_next(items, now)
    end
  end

  describe "lifecycle and refresh" do
    setup do
      user = create_user!()
      :ok = Categories.seed_defaults_for(user)

      on_exit(fn -> Agenda.stop(user.id) end)

      {:ok, user: user}
    end

    test "ensure_started is idempotent", %{user: user} do
      {:ok, pid1} = Agenda.ensure_started(user.id)
      {:ok, pid2} = Agenda.ensure_started(user.id)
      assert pid1 == pid2
    end

    test "primes recurring-todo entries on startup so today picks them up",
         %{user: user} do
      inbox = Categories.inbox_for(user)
      tz = user.timezone || "Etc/UTC"
      now = DateTime.utc_now()

      # Anchor at "noon today (local)" so the entry falls into the
      # day_window even on weekends.
      today_local = DateTime.shift_zone!(now, tz) |> DateTime.to_date()
      {:ok, anchor_local} = DateTime.new(today_local, ~T[12:00:00], tz)
      anchor_utc = DateTime.shift_zone!(anchor_local, "Etc/UTC")

      {:ok, todo} =
        Todo
        |> Ash.Changeset.for_create(
          :create,
          %{
            title: "Bin night",
            category_id: inbox.id,
            recurrence: :weekly,
            recurrence_anchor: anchor_utc
          },
          actor: user
        )
        |> Ash.create()

      # No Entry exists yet — only the Todo template.
      assert Ash.read!(Entry, actor: user) == []

      {:ok, pid} = Agenda.ensure_started(user.id)
      Ecto.Adapters.SQL.Sandbox.allow(Electricbrain.Repo, self(), pid)

      # The Agenda's init calls prime → an Entry should now exist for
      # this todo this week. Force a refresh to be deterministic.
      Agenda.refresh(user.id)
      :ok = Agenda.state(user.id) |> then(fn _ -> :ok end)

      entries = Ash.read!(Entry, actor: user) |> Enum.filter(&(&1.todo_id == todo.id))
      assert length(entries) >= 1
    end

    test "completed entries are hidden from the agenda", %{user: user} do
      {:ok, pid} = Agenda.ensure_started(user.id)
      Ecto.Adapters.SQL.Sandbox.allow(Electricbrain.Repo, self(), pid)

      habit = create_habit!(user)
      now = DateTime.utc_now()

      entry =
        Entry
        |> Ash.Changeset.for_create(
          :create,
          %{
            week_start: DateTime.to_date(now),
            planned_at: DateTime.add(now, 5, :second),
            duration_minutes: 30,
            habit_id: habit.id
          },
          actor: user
        )
        |> Ash.create!()

      Agenda.refresh(user.id)
      %{items: items} = Agenda.state(user.id)
      assert Enum.any?(items, &(&1.entry.id == entry.id))

      entry
      |> Ash.Changeset.for_update(:complete, %{}, actor: user)
      |> Ash.update!()

      Agenda.refresh(user.id)
      %{items: items} = Agenda.state(user.id)
      refute Enum.any?(items, &(&1.entry.id == entry.id))
    end

    test "refresh recomputes and broadcasts when an entry is added", %{user: user} do
      Phoenix.PubSub.subscribe(Electricbrain.PubSub, Agenda.topic(user.id))
      {:ok, pid} = Agenda.ensure_started(user.id)
      Ecto.Adapters.SQL.Sandbox.allow(Electricbrain.Repo, self(), pid)

      habit = create_habit!(user)
      now = DateTime.utc_now()

      Entry
      |> Ash.Changeset.for_create(
        :create,
        %{
          week_start: DateTime.to_date(now),
          planned_at: DateTime.add(now, 5, :second),
          duration_minutes: 30,
          habit_id: habit.id
        },
        actor: user
      )
      |> Ash.create!()

      Agenda.refresh(user.id)

      assert_receive {:agenda_changed, %{current: _, next: next}}, 500
      assert next.entry.habit_id == habit.id
    end
  end

  defp item(id, planned_at, dur_min) do
    %{
      entry: %{id: id, planned_at: planned_at},
      end_time: DateTime.add(planned_at, dur_min * 60, :second),
      duration_minutes: dur_min
    }
  end

  defp create_habit!(user) do
    Habit
    |> Ash.Changeset.for_create(
      :create,
      %{
        title: "Run",
        category_id: Categories.inbox_for(user).id,
        min_count: 1,
        period: :week,
        duration_minutes: 30
      },
      actor: user
    )
    |> Ash.create!()
  end
end
