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
  alias Electricbrain.Training.Generator
  alias Electricbrain.Training.MetricsLog
  alias Electricbrain.Training.Progression
  alias Electricbrain.Training.Template
  alias Electricbrain.Training.TrainingSettings
  alias Electricbrain.Training.Workout
  alias Electricbrain.Training.WorkoutSet

  resources do
    resource Electricbrain.Training.Exercise
    resource Electricbrain.Training.ExerciseState
    resource Electricbrain.Training.Template
    resource Electricbrain.Training.TemplateSlot
    resource Electricbrain.Training.TrainingSettings
    resource Electricbrain.Training.Workout
    resource Electricbrain.Training.WorkoutSet
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

  # ---- session lifecycle ------------------------------------------------

  @doc """
  The next prescribed session for the week view / start flow. Returns
  `%{template, items}` or `{:error, :no_templates}`.
  """
  def next_session(user) do
    exercises = exercises_for(user)

    templates =
      Enum.map(templates_for(user), fn template ->
        %{
          id: template.id,
          name: template.name,
          position: template.position,
          slots:
            Enum.map(template.slots, fn slot ->
              %{
                kind: slot.kind,
                exercise_id: slot.exercise_id,
                exercise_name: slot.exercise && slot.exercise.name,
                sets: slot.sets,
                reps: slot.reps
              }
            end)
        }
      end)

    accessory_pool =
      exercises
      |> Enum.filter(&(&1.progression == :reps))
      |> Enum.sort_by(& &1.name)
      |> Enum.map(&%{id: &1.id, name: &1.name})

    Generator.next_session(%{
      templates: templates,
      last_template_position: last_template_position(user),
      completed_count: completed_count(user),
      accessory_pool: accessory_pool,
      params_by_exercise_id: Map.new(exercises, &{&1.id, exercise_params(&1)}),
      states_by_exercise_id:
        exercises
        |> Enum.filter(& &1.state)
        |> Map.new(&{&1.id, state_map(&1.state)})
    })
  end

  @doc "The user's active workout with ordered sets loaded, or nil."
  def active_workout(user) do
    Workout
    |> Ash.Query.filter(status == :active)
    |> Ash.Query.load(sets: [:exercise])
    |> Ash.read_one!(actor: user)
  end

  @doc """
  Materialises the next prescription into an active Workout + sets.
  Returns `{:ok, workout}` or `{:error, :no_templates | :nothing_prescribed}`
  (the one-active validation surfaces as an Ash error).
  """
  def start_workout!(user) do
    case next_session(user) do
      {:error, :no_templates} ->
        {:error, :no_templates}

      %{items: []} ->
        {:error, :nothing_prescribed}

      %{template: template, items: items} ->
        workout =
          Workout
          |> Ash.Changeset.for_create(
            :start,
            %{template_id: template.id, template_name: template.name},
            actor: user
          )
          |> Ash.create!()

        items
        |> Enum.flat_map(fn item ->
          Enum.map(1..item.sets, fn set_number -> {item, set_number} end)
        end)
        |> Enum.with_index()
        |> Enum.map(fn {{item, set_number}, position} ->
          %{
            workout_id: workout.id,
            exercise_id: item.exercise_id,
            exercise_name: item.exercise_name,
            position: position,
            set_number: set_number,
            slot_kind: item.slot_kind,
            target_reps: item.reps,
            prescribed_weight_kg: item.weight_kg
          }
        end)
        |> Ash.bulk_create!(WorkoutSet, :prescribe,
          actor: user,
          stop_on_error?: true,
          return_errors?: true
        )

        {:ok, active_workout(user)}
    end
  end

  @doc """
  Completes the workout: applies progression per exercise (skipped
  sets count as failures), auto-logs Metrics, broadcasts. Returns the
  completed workout.
  """
  def complete_workout!(user, workout) do
    workout = Ash.load!(workout, [sets: [exercise: [:state]]], actor: user)

    completed =
      workout
      |> Ash.Changeset.for_update(:complete, %{}, actor: user)
      |> Ash.update!()

    workout.sets
    |> Enum.group_by(& &1.exercise_id)
    |> Enum.each(fn {_exercise_id, sets} ->
      exercise = hd(sets).exercise
      results = Enum.map(sets, &%{target_reps: &1.target_reps, actual_reps: &1.actual_reps})

      new_state =
        Progression.apply_result(exercise_params(exercise), state_map(exercise.state), results)

      exercise.state
      |> Ash.Changeset.for_update(
        :advance,
        %{
          current_weight_kg: new_state.current_weight_kg,
          current_reps: new_state.current_reps,
          consecutive_stalls: new_state.consecutive_stalls
        },
        authorize?: false
      )
      |> Ash.update!(authorize?: false)
    end)

    MetricsLog.log_workout!(user, completed)

    completed
  end

  @doc "Abandons the workout — progression and metrics untouched."
  def abandon_workout!(user, workout) do
    workout
    |> Ash.Changeset.for_update(:abandon, %{}, actor: user)
    |> Ash.update!()
  end

  @doc "All-time completed workout count (the accessory rotation clock)."
  def completed_count(user) do
    Workout
    |> Ash.Query.filter(status == :completed)
    |> Ash.count!(actor: user)
  end

  defp last_template_position(user) do
    case Workout
         |> Ash.Query.filter(status == :completed)
         |> Ash.Query.sort(ended_at: :desc)
         |> Ash.Query.limit(1)
         |> Ash.Query.load(:template)
         |> Ash.read_one!(actor: user) do
      %Workout{template: %Template{position: position}} -> position
      _ -> nil
    end
  end

  defp exercise_params(exercise) do
    %{
      progression: exercise.progression,
      increment_kg: exercise.increment_kg,
      start_reps: exercise.start_reps,
      rep_ceiling: exercise.rep_ceiling,
      deload_pct: exercise.deload_pct,
      stall_threshold: exercise.stall_threshold
    }
  end

  defp state_map(state) do
    %{
      current_weight_kg: state.current_weight_kg,
      current_reps: state.current_reps,
      consecutive_stalls: state.consecutive_stalls
    }
  end
end
