defmodule Electricbrain.Meals.WeightTest do
  use Electricbrain.DataCase, async: true

  alias Electricbrain.Meals.NutritionProfile
  alias Electricbrain.Meals.Weight
  alias Electricbrain.Metrics.Measurement
  alias Electricbrain.Metrics.Metric

  # Brisbane is UTC+10 year-round — good for asserting local-week bucketing.
  @tz "Australia/Brisbane"

  defp setup_profile! do
    user = create_user!()

    user =
      user
      |> Ash.Changeset.for_update(:set_timezone, %{timezone: @tz}, actor: user)
      |> Ash.update!(authorize?: false)

    metric =
      Metric
      |> Ash.Changeset.for_create(:create, %{name: "Weight", unit: "kg"}, actor: user)
      |> Ash.create!()

    profile =
      NutritionProfile
      |> Ash.Changeset.for_create(:create, %{weight_metric_id: metric.id}, actor: user)
      |> Ash.create!()

    {user, metric, profile}
  end

  defp measure!(user, metric, value, recorded_at) do
    Ash.Seed.seed!(Measurement, %{
      user_id: user.id,
      metric_id: metric.id,
      value: Decimal.new(to_string(value)),
      recorded_at: recorded_at
    })
  end

  test "latest returns the newest reading" do
    {user, metric, profile} = setup_profile!()
    measure!(user, metric, "91.2", ~U[2026-07-01 20:00:00Z])
    measure!(user, metric, "90.6", ~U[2026-07-08 20:00:00Z])

    assert {:ok, %{kg: kg}} = Weight.latest(user, profile)
    assert Decimal.equal?(kg, Decimal.new("90.6"))
  end

  test "latest is :none without a linked metric or readings" do
    {user, _metric, profile} = setup_profile!()

    assert :none = Weight.latest(user, profile)
    assert :none = Weight.latest(user, %{weight_metric_id: nil})
  end

  test "week_delta compares latest of this local week vs last week" do
    {user, metric, profile} = setup_profile!()

    # "Now" is Saturday 2026-07-11 10:00 Brisbane (00:00 UTC).
    now = ~U[2026-07-11 00:00:00Z]

    # This local week runs from Mon 2026-07-06 00:00 Brisbane = 2026-07-05 14:00 UTC.
    measure!(user, metric, "91.5", ~U[2026-07-02 20:00:00Z])
    measure!(user, metric, "91.0", ~U[2026-07-04 20:00:00Z])
    measure!(user, metric, "90.4", ~U[2026-07-07 20:00:00Z])
    measure!(user, metric, "90.6", ~U[2026-07-09 20:00:00Z])

    assert {:ok, delta} = Weight.week_delta(user, profile, now)
    # latest this week (90.6) - latest last week (91.0)
    assert Decimal.equal?(delta, Decimal.new("-0.4"))
  end

  test "week_delta is :none when a week has no reading" do
    {user, metric, profile} = setup_profile!()
    measure!(user, metric, "90.6", ~U[2026-07-09 20:00:00Z])

    assert :none = Weight.week_delta(user, profile, ~U[2026-07-11 00:00:00Z])
  end
end
