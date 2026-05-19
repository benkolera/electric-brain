defmodule Electricbrain.Planner.EntryTest do
  use Electricbrain.DataCase, async: true

  alias Electricbrain.Categories
  alias Electricbrain.Habits.Habit
  alias Electricbrain.Planner.Entry
  alias Electricbrain.Todos.Todo

  setup do
    user = create_user!()
    :ok = Categories.seed_defaults_for(user)
    inbox = Categories.inbox_for(user)

    todo =
      Todo
      |> Ash.Changeset.for_create(
        :create,
        %{title: "Walk dog", category_id: inbox.id},
        actor: user
      )
      |> Ash.create!()

    habit =
      Habit
      |> Ash.Changeset.for_create(
        :create,
        %{title: "Exercise", category_id: inbox.id, min_count: 3, period: :week},
        actor: user
      )
      |> Ash.create!()

    {:ok, user: user, todo: todo, habit: habit}
  end

  test "creates a floating entry for a todo", %{user: user, todo: todo} do
    assert {:ok, entry} =
             Entry
             |> Ash.Changeset.for_create(
               :create,
               %{todo_id: todo.id, week_start: ~D[2026-05-18]},
               actor: user
             )
             |> Ash.create()

    assert entry.todo_id == todo.id
    assert entry.habit_id == nil
    assert entry.planned_at == nil
    assert entry.week_start == ~D[2026-05-18]
  end

  test "creates a floating entry for a habit", %{user: user, habit: habit} do
    assert {:ok, entry} =
             Entry
             |> Ash.Changeset.for_create(
               :create,
               %{habit_id: habit.id, week_start: ~D[2026-05-18]},
               actor: user
             )
             |> Ash.create()

    assert entry.habit_id == habit.id
    assert entry.todo_id == nil
  end

  test "rejects setting both todo_id and habit_id", %{user: user, todo: todo, habit: habit} do
    assert_raise Ash.Error.Invalid, fn ->
      Entry
      |> Ash.Changeset.for_create(
        :create,
        %{
          todo_id: todo.id,
          habit_id: habit.id,
          week_start: ~D[2026-05-18]
        },
        actor: user
      )
      |> Ash.create!()
    end
  end

  test "rejects setting neither todo_id nor habit_id", %{user: user} do
    assert_raise Ash.Error.Invalid, fn ->
      Entry
      |> Ash.Changeset.for_create(
        :create,
        %{week_start: ~D[2026-05-18]},
        actor: user
      )
      |> Ash.create!()
    end
  end

  test "non-owner cannot attach to someone else's todo", %{todo: todo} do
    bob = create_user!()

    assert {:error, _} =
             Entry
             |> Ash.Changeset.for_create(
               :create,
               %{todo_id: todo.id, week_start: ~D[2026-05-18]},
               actor: bob
             )
             |> Ash.create()
  end

  test "schedule sets planned_at", %{user: user, todo: todo} do
    entry =
      Entry
      |> Ash.Changeset.for_create(
        :create,
        %{todo_id: todo.id, week_start: ~D[2026-05-18]},
        actor: user
      )
      |> Ash.create!()

    when_dt = ~U[2026-05-20 18:00:00.000000Z]

    {:ok, scheduled} =
      entry
      |> Ash.Changeset.for_update(:schedule, %{planned_at: when_dt}, actor: user)
      |> Ash.update()

    assert DateTime.compare(scheduled.planned_at, when_dt) == :eq
  end

  test "unschedule clears planned_at", %{user: user, todo: todo} do
    entry =
      Entry
      |> Ash.Changeset.for_create(
        :create,
        %{
          todo_id: todo.id,
          week_start: ~D[2026-05-18],
          planned_at: ~U[2026-05-20 18:00:00.000000Z]
        },
        actor: user
      )
      |> Ash.create!()

    {:ok, unscheduled} =
      entry
      |> Ash.Changeset.for_update(:unschedule, %{}, actor: user)
      |> Ash.update()

    assert unscheduled.planned_at == nil
  end

  test "destroying a todo cascade-deletes its entries", %{user: user, todo: todo} do
    Entry
    |> Ash.Changeset.for_create(
      :create,
      %{todo_id: todo.id, week_start: ~D[2026-05-18]},
      actor: user
    )
    |> Ash.create!()

    assert length(Ash.read!(Entry, actor: user)) == 1

    Ash.destroy!(todo, actor: user)
    assert Ash.read!(Entry, actor: user) == []
  end

  test "user only sees their own entries", %{user: alice, todo: todo} do
    bob = create_user!()

    Entry
    |> Ash.Changeset.for_create(
      :create,
      %{todo_id: todo.id, week_start: ~D[2026-05-18]},
      actor: alice
    )
    |> Ash.create!()

    assert Entry |> Ash.read!(actor: bob) == []
    assert length(Entry |> Ash.read!(actor: alice)) == 1
  end
end
