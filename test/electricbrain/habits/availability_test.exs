defmodule Electricbrain.Habits.AvailabilityTest do
  use Electricbrain.DataCase, async: true

  alias Electricbrain.Categories
  alias Electricbrain.Habits.Availability
  alias Electricbrain.Habits.Habit

  setup do
    user = create_user!()
    :ok = Categories.seed_defaults_for(user)
    inbox = Categories.inbox_for(user)

    habit =
      Habit
      |> Ash.Changeset.for_create(
        :create,
        %{title: "Exercise", category_id: inbox.id, min_count: 3, period: :week},
        actor: user
      )
      |> Ash.create!()

    {:ok, user: user, habit: habit}
  end

  test "creates an availability window", %{user: user, habit: habit} do
    assert {:ok, availability} =
             Availability
             |> Ash.Changeset.for_create(
               :create,
               %{
                 habit_id: habit.id,
                 day_of_week: 3,
                 start_time: ~T[18:00:00],
                 end_time: ~T[19:00:00]
               },
               actor: user
             )
             |> Ash.create()

    assert availability.day_of_week == 3
    assert availability.user_id == user.id
  end

  test "rejects end_time <= start_time", %{user: user, habit: habit} do
    assert {:error, _} =
             Availability
             |> Ash.Changeset.for_create(
               :create,
               %{
                 habit_id: habit.id,
                 day_of_week: 3,
                 start_time: ~T[19:00:00],
                 end_time: ~T[18:00:00]
               },
               actor: user
             )
             |> Ash.create()
  end

  test "destroying a habit cascade-deletes its availabilities", %{user: user, habit: habit} do
    Availability
    |> Ash.Changeset.for_create(
      :create,
      %{
        habit_id: habit.id,
        day_of_week: 1,
        start_time: ~T[09:00:00],
        end_time: ~T[10:00:00]
      },
      actor: user
    )
    |> Ash.create!()

    assert length(Ash.read!(Availability, actor: user)) == 1

    Ash.destroy!(habit, actor: user)
    assert Ash.read!(Availability, actor: user) == []
  end

  test "day_of_week must be 1-7", %{user: user, habit: habit} do
    assert {:error, _} =
             Availability
             |> Ash.Changeset.for_create(
               :create,
               %{
                 habit_id: habit.id,
                 day_of_week: 8,
                 start_time: ~T[09:00:00],
                 end_time: ~T[10:00:00]
               },
               actor: user
             )
             |> Ash.create()
  end

  test "non-owner cannot create against another user's habit", %{habit: habit} do
    bob = create_user!()

    assert {:error, _} =
             Availability
             |> Ash.Changeset.for_create(
               :create,
               %{
                 habit_id: habit.id,
                 day_of_week: 1,
                 start_time: ~T[09:00:00],
                 end_time: ~T[10:00:00]
               },
               actor: bob
             )
             |> Ash.create()
  end
end
