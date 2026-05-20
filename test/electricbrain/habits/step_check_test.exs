defmodule Electricbrain.Habits.StepCheckTest do
  use Electricbrain.DataCase, async: true

  alias Electricbrain.Categories
  alias Electricbrain.Habits.Completion
  alias Electricbrain.Habits.Habit
  alias Electricbrain.Habits.RitualStep
  alias Electricbrain.Habits.StepCheck

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

    step =
      RitualStep
      |> Ash.Changeset.for_create(
        :create,
        %{habit_id: habit.id, title: "brush teeth"},
        actor: user
      )
      |> Ash.create!()

    completion =
      Completion
      |> Ash.Changeset.for_create(:start, %{habit_id: habit.id}, actor: user)
      |> Ash.create!()

    {:ok, user: user, habit: habit, step: step, completion: completion}
  end

  test "in-progress completion has nil completed_at", %{completion: completion} do
    assert is_nil(completion.completed_at)
  end

  test "finalize sets completed_at", %{user: user, completion: completion} do
    finalized =
      completion
      |> Ash.Changeset.for_update(:finalize, %{}, actor: user)
      |> Ash.update!()

    refute is_nil(finalized.completed_at)
  end

  test "creates a step check", %{user: user, step: step, completion: completion} do
    assert {:ok, check} =
             StepCheck
             |> Ash.Changeset.for_create(
               :create,
               %{completion_id: completion.id, ritual_step_id: step.id},
               actor: user
             )
             |> Ash.create()

    assert check.completion_id == completion.id
    assert check.ritual_step_id == step.id
  end

  test "rejects a duplicate check for the same (completion, step)", %{
    user: user,
    step: step,
    completion: completion
  } do
    StepCheck
    |> Ash.Changeset.for_create(
      :create,
      %{completion_id: completion.id, ritual_step_id: step.id},
      actor: user
    )
    |> Ash.create!()

    assert {:error, _} =
             StepCheck
             |> Ash.Changeset.for_create(
               :create,
               %{completion_id: completion.id, ritual_step_id: step.id},
               actor: user
             )
             |> Ash.create()
  end

  test "destroying a step cascade-deletes its checks", %{
    user: user,
    step: step,
    completion: completion
  } do
    StepCheck
    |> Ash.Changeset.for_create(
      :create,
      %{completion_id: completion.id, ritual_step_id: step.id},
      actor: user
    )
    |> Ash.create!()

    Ash.destroy!(step, actor: user)
    assert Ash.read!(StepCheck, actor: user) == []
  end
end
