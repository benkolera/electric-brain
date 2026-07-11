defmodule Electricbrain.Meals.ProfileMetricTest do
  use Electricbrain.DataCase, async: true

  require Ash.Query

  alias Electricbrain.Meals
  alias Electricbrain.Meals.NutritionProfile
  alias Electricbrain.Meals.ProfileMetric
  alias Electricbrain.Metrics.Metric

  defp setup_profile! do
    user = create_user!()

    profile =
      NutritionProfile
      |> Ash.Changeset.for_create(:create, %{}, actor: user)
      |> Ash.create!()

    {user, profile}
  end

  defp metric!(user, name) do
    Metric
    |> Ash.Changeset.for_create(:create, %{name: name, unit: "kg"}, actor: user)
    |> Ash.create!()
  end

  test "set_feedback_metrics replaces links in order" do
    {user, profile} = setup_profile!()
    weight = metric!(user, "Weight")
    waist = metric!(user, "Waist")

    :ok = Meals.set_feedback_metrics(user, profile, [waist.id, weight.id])

    assert [first, second] = Meals.feedback_metrics(user, profile)
    assert first.metric.name == "Waist"
    assert second.metric.name == "Weight"

    # Re-save with just one — the other link disappears.
    :ok = Meals.set_feedback_metrics(user, profile, [weight.id])

    assert [only] = Meals.feedback_metrics(user, profile)
    assert only.metric.name == "Weight"
  end

  test "cannot link another user's metric" do
    {user, profile} = setup_profile!()
    other = create_user!()
    theirs = metric!(other, "Their weight")

    assert {:error, _} =
             ProfileMetric
             |> Ash.Changeset.for_create(
               :create,
               %{nutrition_profile_id: profile.id, metric_id: theirs.id, position: 0},
               actor: user
             )
             |> Ash.create()
  end

  test "links are invisible to other users" do
    {user, profile} = setup_profile!()
    weight = metric!(user, "Weight")
    :ok = Meals.set_feedback_metrics(user, profile, [weight.id])

    other = create_user!()
    assert [] = Ash.read!(ProfileMetric, actor: other)
  end

  test "deleting the metric removes the link" do
    {user, profile} = setup_profile!()
    weight = metric!(user, "Weight")
    :ok = Meals.set_feedback_metrics(user, profile, [weight.id])

    :ok = Ash.destroy(weight, actor: user)

    assert [] = Meals.feedback_metrics(user, profile)
  end
end
