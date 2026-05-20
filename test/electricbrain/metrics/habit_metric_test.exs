defmodule Electricbrain.Metrics.HabitMetricTest do
  use Electricbrain.DataCase, async: true

  alias Electricbrain.Categories
  alias Electricbrain.Habits.Habit
  alias Electricbrain.Metrics.HabitMetric
  alias Electricbrain.Metrics.Metric

  setup do
    user = create_user!()
    :ok = Categories.seed_defaults_for(user)
    inbox = Categories.inbox_for(user)

    {:ok, habit} =
      Habit
      |> Ash.Changeset.for_create(
        :create,
        %{title: "Lift", category_id: inbox.id, min_count: 1, period: :day},
        actor: user
      )
      |> Ash.create()

    {:ok, metric} =
      Metric
      |> Ash.Changeset.for_create(:create, %{name: "1RM", unit: "kg"}, actor: user)
      |> Ash.create()

    {:ok, user: user, habit: habit, metric: metric}
  end

  test "attaches a metric to a habit", %{user: user, habit: habit, metric: metric} do
    assert {:ok, _link} =
             HabitMetric
             |> Ash.Changeset.for_create(
               :create,
               %{habit_id: habit.id, metric_id: metric.id},
               actor: user
             )
             |> Ash.create()

    loaded = Ash.get!(Habit, habit.id, actor: user, load: [:metrics])
    assert Enum.map(loaded.metrics, & &1.id) == [metric.id]
  end

  test "rejects duplicate attach", %{user: user, habit: habit, metric: metric} do
    HabitMetric
    |> Ash.Changeset.for_create(
      :create,
      %{habit_id: habit.id, metric_id: metric.id},
      actor: user
    )
    |> Ash.create!()

    assert {:error, _} =
             HabitMetric
             |> Ash.Changeset.for_create(
               :create,
               %{habit_id: habit.id, metric_id: metric.id},
               actor: user
             )
             |> Ash.create()
  end

  test "rejects attaching another user's metric", %{user: user, habit: habit} do
    other_user = create_user!()

    {:ok, other_metric} =
      Metric
      |> Ash.Changeset.for_create(:create, %{name: "x", unit: "x"}, actor: other_user)
      |> Ash.create()

    assert {:error, _} =
             HabitMetric
             |> Ash.Changeset.for_create(
               :create,
               %{habit_id: habit.id, metric_id: other_metric.id},
               actor: user
             )
             |> Ash.create()
  end
end
