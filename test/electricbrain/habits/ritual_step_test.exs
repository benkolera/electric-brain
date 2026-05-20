defmodule Electricbrain.Habits.RitualStepTest do
  use Electricbrain.DataCase, async: true

  alias Electricbrain.Categories
  alias Electricbrain.Habits.Habit
  alias Electricbrain.Habits.RitualStep

  setup do
    user = create_user!()
    :ok = Categories.seed_defaults_for(user)
    inbox = Categories.inbox_for(user)

    habit =
      Habit
      |> Ash.Changeset.for_create(
        :create,
        %{title: "Bedtime", category_id: inbox.id, fixed_schedule: true},
        actor: user
      )
      |> Ash.create!()

    {:ok, user: user, habit: habit}
  end

  test "creates a ritual step", %{user: user, habit: habit} do
    assert {:ok, step} =
             RitualStep
             |> Ash.Changeset.for_create(
               :create,
               %{habit_id: habit.id, title: "brush teeth"},
               actor: user
             )
             |> Ash.create()

    assert step.title == "brush teeth"
    assert step.user_id == user.id
  end

  test "destroying a habit cascade-deletes its steps", %{user: user, habit: habit} do
    RitualStep
    |> Ash.Changeset.for_create(
      :create,
      %{habit_id: habit.id, title: "screens off"},
      actor: user
    )
    |> Ash.create!()

    assert length(Ash.read!(RitualStep, actor: user)) == 1

    Ash.destroy!(habit, actor: user)
    assert Ash.read!(RitualStep, actor: user) == []
  end

  test "non-owner cannot create a step against another user's habit", %{habit: habit} do
    bob = create_user!()

    assert {:error, _} =
             RitualStep
             |> Ash.Changeset.for_create(
               :create,
               %{habit_id: habit.id, title: "sneaky"},
               actor: bob
             )
             |> Ash.create()
  end
end
