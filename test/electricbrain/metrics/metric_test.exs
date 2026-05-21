defmodule Electricbrain.Metrics.MetricTest do
  use Electricbrain.DataCase, async: true

  alias Electricbrain.Categories
  alias Electricbrain.Metrics.Metric

  describe "create/1" do
    test "defaults aggregation to :point" do
      user = create_user!()
      :ok = Categories.seed_defaults_for(user)

      assert {:ok, metric} =
               Metric
               |> Ash.Changeset.for_create(
                 :create,
                 %{name: "Weight", unit: "kg"},
                 actor: user
               )
               |> Ash.create()

      assert metric.aggregation == :point
      assert metric.user_id == user.id
    end

    test "accepts :sum aggregation and a group_name (period required)" do
      user = create_user!()

      assert {:ok, metric} =
               Metric
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   name: "Water",
                   unit: "L",
                   aggregation: :sum,
                   period: :day,
                   group_name: "Hydration"
                 },
                 actor: user
               )
               |> Ash.create()

      assert metric.aggregation == :sum
      assert metric.period == :day
      assert metric.group_name == "Hydration"
    end

    test "requires name and unit" do
      user = create_user!()

      assert {:error, _} =
               Metric
               |> Ash.Changeset.for_create(:create, %{unit: "kg"}, actor: user)
               |> Ash.create()

      assert {:error, _} =
               Metric
               |> Ash.Changeset.for_create(:create, %{name: "Weight"}, actor: user)
               |> Ash.create()
    end

    test ":sum aggregation requires a period" do
      user = create_user!()

      assert {:error, _} =
               Metric
               |> Ash.Changeset.for_create(
                 :create,
                 %{name: "Water", unit: "L", aggregation: :sum},
                 actor: user
               )
               |> Ash.create()

      assert {:ok, _} =
               Metric
               |> Ash.Changeset.for_create(
                 :create,
                 %{name: "Water", unit: "L", aggregation: :sum, period: :day},
                 actor: user
               )
               |> Ash.create()
    end

    test "goal_kind and goal_value must be set together" do
      user = create_user!()

      assert {:error, _} =
               Metric
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   name: "Weight",
                   unit: "kg",
                   period: :day,
                   goal_kind: :at_least
                 },
                 actor: user
               )
               |> Ash.create()

      assert {:error, _} =
               Metric
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   name: "Weight",
                   unit: "kg",
                   period: :day,
                   goal_value: Decimal.new("80")
                 },
                 actor: user
               )
               |> Ash.create()
    end

    test "a configured goal requires a period" do
      user = create_user!()

      assert {:error, _} =
               Metric
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   name: "Weight",
                   unit: "kg",
                   goal_kind: :at_most,
                   goal_value: Decimal.new("80")
                 },
                 actor: user
               )
               |> Ash.create()
    end

    test "is scoped to the actor" do
      user1 = create_user!()
      user2 = create_user!()

      {:ok, m1} =
        Metric
        |> Ash.Changeset.for_create(:create, %{name: "U1", unit: "x"}, actor: user1)
        |> Ash.create()

      assert Enum.map(Ash.read!(Metric, actor: user1), & &1.id) == [m1.id]
      assert Ash.read!(Metric, actor: user2) == []
    end
  end
end
