defmodule Electricbrain.Metrics.MeasurementTest do
  use Electricbrain.DataCase, async: true

  alias Electricbrain.Habits.Completion
  alias Electricbrain.Habits.Habit
  alias Electricbrain.Categories
  alias Electricbrain.Metrics.Measurement
  alias Electricbrain.Metrics.Metric

  setup do
    user = create_user!()
    :ok = Categories.seed_defaults_for(user)
    inbox = Categories.inbox_for(user)

    {:ok, metric} =
      Metric
      |> Ash.Changeset.for_create(:create, %{name: "Weight", unit: "kg"}, actor: user)
      |> Ash.create()

    {:ok, user: user, inbox: inbox, metric: metric}
  end

  describe "create/1" do
    test "defaults recorded_at to now when absent", %{user: user, metric: metric} do
      before = DateTime.utc_now()

      {:ok, m} =
        Measurement
        |> Ash.Changeset.for_create(
          :create,
          %{metric_id: metric.id, value: Decimal.new("82.5")},
          actor: user
        )
        |> Ash.create()

      assert DateTime.compare(m.recorded_at, before) != :lt
      assert Decimal.equal?(m.value, Decimal.new("82.5"))
    end

    test "accepts negative values", %{user: user, metric: metric} do
      assert {:ok, m} =
               Measurement
               |> Ash.Changeset.for_create(
                 :create,
                 %{metric_id: metric.id, value: Decimal.new("-1.2")},
                 actor: user
               )
               |> Ash.create()

      assert Decimal.equal?(m.value, Decimal.new("-1.2"))
    end

    test "rejects future recorded_at", %{user: user, metric: metric} do
      future = DateTime.add(DateTime.utc_now(), 60 * 60, :second)

      assert {:error, _} =
               Measurement
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   metric_id: metric.id,
                   value: Decimal.new("1"),
                   recorded_at: future
                 },
                 actor: user
               )
               |> Ash.create()
    end

    test "allows backfilled recorded_at in the past", %{user: user, metric: metric} do
      past = DateTime.add(DateTime.utc_now(), -7 * 86_400, :second)

      assert {:ok, m} =
               Measurement
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   metric_id: metric.id,
                   value: Decimal.new("80"),
                   recorded_at: past
                 },
                 actor: user
               )
               |> Ash.create()

      assert DateTime.compare(m.recorded_at, past) == :eq
    end

    test "can link to a habit completion", %{user: user, inbox: inbox, metric: metric} do
      {:ok, habit} =
        Habit
        |> Ash.Changeset.for_create(
          :create,
          %{title: "Track weight", category_id: inbox.id, min_count: 1, period: :day},
          actor: user
        )
        |> Ash.create()

      {:ok, completion} =
        Completion
        |> Ash.Changeset.for_create(:create, %{habit_id: habit.id}, actor: user)
        |> Ash.create()

      {:ok, m} =
        Measurement
        |> Ash.Changeset.for_create(
          :create,
          %{
            metric_id: metric.id,
            completion_id: completion.id,
            value: Decimal.new("82")
          },
          actor: user
        )
        |> Ash.create()

      assert m.completion_id == completion.id
    end
  end
end
