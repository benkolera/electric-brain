defmodule Electricbrain.Notifications.SchedulerTest do
  use Electricbrain.DataCase, async: false

  alias Electricbrain.Categories
  alias Electricbrain.Notifications.Scheduler
  alias Electricbrain.Planner.Entry
  alias Electricbrain.Todos.Todo

  setup do
    user = create_user!()
    :ok = Categories.seed_defaults_for(user)
    inbox = Categories.inbox_for(user)

    {:ok, todo} =
      Todo
      |> Ash.Changeset.for_create(
        :create,
        %{title: "Standup", category_id: inbox.id},
        actor: user
      )
      |> Ash.create()

    {:ok, user: user, inbox: inbox, todo: todo}
  end

  defp create_entry!(user, todo, planned_at) do
    Entry
    |> Ash.Changeset.for_create(
      :create,
      %{
        todo_id: todo.id,
        week_start: Date.utc_today() |> Date.beginning_of_week(),
        planned_at: planned_at
      },
      actor: user
    )
    |> Ash.create!()
  end

  test "marks entries with planned_at inside the lead window as notified",
       %{user: user, todo: todo} do
    now = DateTime.utc_now()
    in_three_min = DateTime.add(now, 3 * 60, :second)
    in_ten_min = DateTime.add(now, 10 * 60, :second)

    due = create_entry!(user, todo, in_three_min)
    not_due = create_entry!(user, todo, in_ten_min)

    assert Scheduler.run_once(now) == 1

    assert refetch(due).notified_at != nil
    assert refetch(not_due).notified_at == nil
  end

  test "doesn't re-notify entries that are already notified",
       %{user: user, todo: todo} do
    now = DateTime.utc_now()
    in_three_min = DateTime.add(now, 3 * 60, :second)

    create_entry!(user, todo, in_three_min)
    assert Scheduler.run_once(now) == 1
    assert Scheduler.run_once(now) == 0
  end

  test "rescheduling an entry clears notified_at so it can fire again",
       %{user: user, todo: todo} do
    now = DateTime.utc_now()
    entry = create_entry!(user, todo, DateTime.add(now, 3 * 60, :second))

    assert Scheduler.run_once(now) == 1
    assert refetch(entry).notified_at != nil

    # Reschedule to a fresh upcoming time → notified_at cleared.
    entry
    |> Ash.Changeset.for_update(
      :schedule,
      %{planned_at: DateTime.add(now, 4 * 60, :second)},
      actor: user
    )
    |> Ash.update!()

    assert refetch(entry).notified_at == nil
    assert Scheduler.run_once(now) == 1
  end

  defp refetch(entry) do
    Ash.get!(Entry, entry.id, authorize?: false)
  end
end
