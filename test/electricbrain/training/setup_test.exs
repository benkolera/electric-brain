defmodule Electricbrain.Training.SetupTest do
  use Electricbrain.DataCase, async: true

  require Ash.Query

  alias Electricbrain.Training
  alias Electricbrain.Training.Exercise
  alias Electricbrain.Training.ExerciseState
  alias Electricbrain.Training.Template
  alias Electricbrain.Training.TemplateSlot

  describe "ensure_setup!/1" do
    test "seeds the 10-exercise pool with states and the A/B templates" do
      user = create_user!()
      :ok = Training.ensure_setup!(user)

      exercises = Training.exercises_for(user)
      assert length(exercises) == 10

      squat = Enum.find(exercises, &(&1.name == "Back squat"))
      assert squat.kind == :barbell
      assert squat.progression == :weight
      assert Decimal.equal?(squat.increment_kg, Decimal.new("2.5"))
      assert Decimal.equal?(squat.state.current_weight_kg, Decimal.new(20))

      deadlift = Enum.find(exercises, &(&1.name == "Deadlift"))
      assert Decimal.equal?(deadlift.increment_kg, Decimal.new(5))
      assert Decimal.equal?(deadlift.state.current_weight_kg, Decimal.new(40))

      swings = Enum.find(exercises, &(&1.name == "KB single-arm swings"))
      assert swings.progression == :reps
      assert swings.rep_ceiling == 20
      assert swings.state.current_reps == 10
      assert Decimal.equal?(swings.state.current_weight_kg, Decimal.new(16))

      pull_ups = Enum.find(exercises, &(&1.name == "Pull ups"))
      assert is_nil(pull_ups.increment_kg)
      assert is_nil(pull_ups.rep_ceiling)
      assert pull_ups.state.current_reps == 5
      assert is_nil(pull_ups.state.current_weight_kg)

      [a, b] = Training.templates_for(user)
      assert a.name == "A"
      assert b.name == "B"

      assert Enum.map(a.slots, &{&1.kind, &1.exercise && &1.exercise.name, &1.sets, &1.reps}) ==
               [
                 {:fixed, "Back squat", 5, 5},
                 {:fixed, "Bench press", 5, 5},
                 {:fixed, "Barbell row", 5, 5},
                 {:accessory, nil, 3, nil},
                 {:accessory, nil, 3, nil}
               ]

      deadlift_slot = Enum.find(b.slots, &(&1.exercise && &1.exercise.name == "Deadlift"))
      assert deadlift_slot.sets == 1
      assert deadlift_slot.reps == 5
    end

    test "is idempotent" do
      user = create_user!()
      :ok = Training.ensure_setup!(user)
      :ok = Training.ensure_setup!(user)

      assert length(Training.exercises_for(user)) == 10
      assert length(Training.templates_for(user)) == 2
    end
  end

  describe "settings_for/1" do
    test "creates defaults on first read, then reuses" do
      user = create_user!()

      settings = Training.settings_for(user)
      assert settings.training_days == [1, 3, 5]
      assert settings.reminder_time == ~T[06:30:00]
      assert settings.default_rest_seconds == 180

      assert Training.settings_for(user).id == settings.id
    end

    test "rejects invalid training days" do
      user = create_user!()
      settings = Training.settings_for(user)

      assert {:error, _} =
               settings
               |> Ash.Changeset.for_update(:update, %{training_days: [0, 3]}, actor: user)
               |> Ash.update()

      assert {:error, _} =
               settings
               |> Ash.Changeset.for_update(:update, %{training_days: []}, actor: user)
               |> Ash.update()
    end
  end

  describe "policies" do
    test "training rows are invisible to other users" do
      user = create_user!()
      other = create_user!()
      :ok = Training.ensure_setup!(user)

      assert [] = Ash.read!(Exercise, actor: other)
      assert [] = Ash.read!(ExerciseState, actor: other)
      assert [] = Ash.read!(Template, actor: other)
      assert [] = Ash.read!(TemplateSlot, actor: other)
    end
  end

  describe "slot consistency" do
    test "fixed slots need an exercise and reps; accessory slots must not pin one" do
      user = create_user!()
      :ok = Training.ensure_setup!(user)
      [a | _] = Training.templates_for(user)
      squat = Enum.find(Training.exercises_for(user), &(&1.name == "Back squat"))

      assert {:error, _} =
               TemplateSlot
               |> Ash.Changeset.for_create(
                 :create,
                 %{template_id: a.id, position: 9, kind: :fixed, sets: 5},
                 actor: user
               )
               |> Ash.create()

      assert {:error, _} =
               TemplateSlot
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   template_id: a.id,
                   position: 9,
                   kind: :accessory,
                   exercise_id: squat.id,
                   sets: 3
                 },
                 actor: user
               )
               |> Ash.create()
    end
  end

  describe "state edits" do
    test "changing the weight resets the stall count" do
      user = create_user!()
      :ok = Training.ensure_setup!(user)
      squat = Enum.find(Training.exercises_for(user), &(&1.name == "Back squat"))

      state =
        squat.state
        |> Ash.Changeset.for_update(:advance, %{consecutive_stalls: 2}, authorize?: false)
        |> Ash.update!(authorize?: false)

      updated =
        state
        |> Ash.Changeset.for_update(:update, %{current_weight_kg: "80"}, actor: user)
        |> Ash.update!()

      assert updated.consecutive_stalls == 0
      assert Decimal.equal?(updated.current_weight_kg, Decimal.new(80))
    end
  end
end
