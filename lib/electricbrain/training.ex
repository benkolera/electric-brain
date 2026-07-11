defmodule Electricbrain.Training do
  @moduledoc """
  Strength training: a linear A/B programme over the user's exercise
  pool, an in-gym logging flow, and automatic Metrics logging. See
  `Training.Defaults` for the seeded pool and templates,
  `Training.Progression` for the maths, and `Training.Generator` for
  session prescription.
  """

  use Ash.Domain,
    otp_app: :electricbrain

  require Ash.Query

  alias Electricbrain.Training.Defaults
  alias Electricbrain.Training.Exercise
  alias Electricbrain.Training.ExerciseState
  alias Electricbrain.Training.Template
  alias Electricbrain.Training.TrainingSettings

  resources do
    resource Electricbrain.Training.Exercise
    resource Electricbrain.Training.ExerciseState
    resource Electricbrain.Training.Template
    resource Electricbrain.Training.TemplateSlot
    resource Electricbrain.Training.TrainingSettings
  end

  @doc "PubSub topic for a user's live training state."
  def topic(user_id), do: "training:user:#{user_id}"

  @doc """
  Idempotent first-visit setup: seeds the default exercise pool (with
  starting states) and the A/B templates from `Training.Defaults`.
  No-op once the user has any exercises.
  """
  def ensure_setup!(user) do
    if Ash.exists?(Ash.Query.filter(Exercise, user_id == ^user.id), authorize?: false) do
      :ok
    else
      exercises_by_name =
        Map.new(Defaults.exercises(), fn spec ->
          exercise =
            Exercise
            |> Ash.Changeset.for_create(
              :create,
              Map.take(spec, [
                :name,
                :kind,
                :progression,
                :increment_kg,
                :start_reps,
                :rep_ceiling
              ]),
              actor: user
            )
            |> Ash.create!()

          ExerciseState
          |> Ash.Changeset.for_create(
            :create,
            %{
              exercise_id: exercise.id,
              current_weight_kg: spec[:start_weight_kg],
              current_reps: spec[:start_reps]
            },
            actor: user
          )
          |> Ash.create!()

          {spec.name, exercise}
        end)

      Enum.each(Defaults.templates(), fn template_spec ->
        slots =
          Enum.map(template_spec.slots, fn slot ->
            %{
              position: slot.position,
              kind: slot.kind,
              exercise_id: slot[:exercise] && exercises_by_name[slot[:exercise]].id,
              sets: slot.sets,
              reps: slot[:reps]
            }
          end)

        Template
        |> Ash.Changeset.for_create(
          :create,
          %{name: template_spec.name, position: template_spec.position, slots: slots},
          actor: user
        )
        |> Ash.create!()
      end)

      :ok
    end
  end

  @doc "The user's training settings, created with defaults on first read."
  def settings_for(user) do
    case TrainingSettings
         |> Ash.Query.filter(user_id == ^user.id)
         |> Ash.read_one!(actor: user) do
      nil ->
        TrainingSettings
        |> Ash.Changeset.for_create(:create, %{}, actor: user)
        |> Ash.create!()

      settings ->
        settings
    end
  end

  @doc "The user's exercises sorted by name, with progression state loaded."
  def exercises_for(user) do
    Exercise
    |> Ash.Query.sort(name: :asc)
    |> Ash.Query.load(:state)
    |> Ash.read!(actor: user)
  end

  @doc "The user's templates in rotation order, slots (and their exercises) loaded."
  def templates_for(user) do
    Template
    |> Ash.Query.sort(position: :asc)
    |> Ash.Query.load(slots: [:exercise])
    |> Ash.read!(actor: user)
  end
end
