defmodule Electricbrain.Training.Validations.SlotExerciseConsistency do
  @moduledoc """
  A `:fixed` slot must pin an exercise (and needs target reps); an
  `:accessory` slot must not — the generator fills it from the
  rotating pool and target reps come from the exercise's state.
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    kind = Ash.Changeset.get_attribute(changeset, :kind)
    exercise_id = Ash.Changeset.get_attribute(changeset, :exercise_id)
    reps = Ash.Changeset.get_attribute(changeset, :reps)

    case kind do
      :fixed ->
        cond do
          is_nil(exercise_id) ->
            {:error, field: :exercise_id, message: "a fixed slot must pin an exercise"}

          is_nil(reps) ->
            {:error, field: :reps, message: "a fixed slot needs target reps"}

          true ->
            :ok
        end

      :accessory ->
        if is_nil(exercise_id) do
          :ok
        else
          {:error,
           field: :exercise_id,
           message: "an accessory slot rotates through the pool — switch to fixed to pin"}
        end
    end
  end
end
