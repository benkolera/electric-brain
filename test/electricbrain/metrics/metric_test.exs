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

    test "accepts :sum aggregation and a group_name" do
      user = create_user!()

      assert {:ok, metric} =
               Metric
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   name: "Deadlift 1RM",
                   unit: "kg",
                   aggregation: :sum,
                   group_name: "Deadlift"
                 },
                 actor: user
               )
               |> Ash.create()

      assert metric.aggregation == :sum
      assert metric.group_name == "Deadlift"
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
