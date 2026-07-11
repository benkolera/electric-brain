defmodule Electricbrain.Training.MetricsLog do
  @moduledoc """
  Writes a completed workout's lifts into Metrics: per weight-mode
  exercise with at least one completed set, the top working weight
  and the best Epley e1RM across completed sets.

  Series are resolved by EXPLICIT metric id stored on the exercise
  (`top_set_metric_id` / `e1rm_metric_id`) — created on first log and
  linked, so renaming a metric never forks a new series (the Oura
  by-name lesson). Both series share `group_name: exercise.name` so
  they cluster on one chart. Idempotent via
  `workout.metrics_logged_at`.
  """

  require Ash.Query

  alias Electricbrain.Metrics.Measurement
  alias Electricbrain.Metrics.Metric
  alias Electricbrain.Training.Exercise
  alias Electricbrain.Training.Progression

  @doc "Returns the number of measurements written (0 when already logged)."
  def log_workout!(user, workout) do
    if workout.metrics_logged_at do
      0
    else
      workout = Ash.load!(workout, [sets: [:exercise]], actor: user)

      count =
        workout.sets
        |> Enum.filter(&(&1.exercise.progression == :weight and completed?(&1)))
        |> Enum.group_by(& &1.exercise_id)
        |> Enum.reduce(0, fn {_exercise_id, sets}, acc ->
          acc + log_exercise!(user, hd(sets).exercise, sets, workout.ended_at)
        end)

      workout
      |> Ash.Changeset.for_update(:mark_metrics_logged, %{}, authorize?: false)
      |> Ash.update!(authorize?: false)

      count
    end
  end

  defp completed?(set), do: is_integer(set.actual_reps) and set.actual_reps >= 1

  defp log_exercise!(user, exercise, sets, recorded_at) do
    top_set =
      sets
      |> Enum.map(& &1.prescribed_weight_kg)
      |> Enum.reject(&is_nil/1)
      |> Enum.max_by(&Decimal.to_float/1, fn -> nil end)

    if is_nil(top_set) do
      0
    else
      best_e1rm =
        sets
        |> Enum.map(&Progression.epley_e1rm(&1.prescribed_weight_kg, &1.actual_reps))
        |> Enum.max_by(&Decimal.to_float/1)

      exercise = ensure_metrics!(user, exercise)

      measure!(user, exercise.top_set_metric_id, top_set, recorded_at)
      measure!(user, exercise.e1rm_metric_id, best_e1rm, recorded_at)
      2
    end
  end

  defp ensure_metrics!(_user, %Exercise{top_set_metric_id: id, e1rm_metric_id: id2} = exercise)
       when is_binary(id) and is_binary(id2),
       do: exercise

  defp ensure_metrics!(user, exercise) do
    top = exercise.top_set_metric_id || create_metric!(user, "#{exercise.name} top set", exercise)
    e1rm = exercise.e1rm_metric_id || create_metric!(user, "#{exercise.name} e1RM", exercise)

    exercise
    |> Ash.Changeset.for_update(
      :link_metrics,
      %{top_set_metric_id: metric_id(top), e1rm_metric_id: metric_id(e1rm)},
      actor: user
    )
    |> Ash.update!()
  end

  defp metric_id(%Metric{id: id}), do: id
  defp metric_id(id) when is_binary(id), do: id

  defp create_metric!(user, name, exercise) do
    Metric
    |> Ash.Changeset.for_create(
      :create,
      %{
        name: name,
        unit: "kg",
        aggregation: :point,
        period: :day,
        group_name: exercise.name
      },
      actor: user
    )
    |> Ash.create!()
  end

  defp measure!(user, metric_id, value, recorded_at) do
    Measurement
    |> Ash.Changeset.for_create(
      :create,
      %{metric_id: metric_id, value: value, recorded_at: recorded_at},
      actor: user
    )
    |> Ash.create!()
  end
end
