defmodule ElectricbrainWeb.MealLive.SettingsTest do
  use ElectricbrainWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Electricbrain.Meals
  alias Electricbrain.Metrics.Measurement
  alias Electricbrain.Metrics.Metric

  setup %{conn: conn} do
    user = create_user!()
    {:ok, conn: log_in_user(conn, user), user: user}
  end

  test "creates a profile and shows computed targets from the weight metric", %{
    conn: conn,
    user: user
  } do
    metric =
      Metric
      |> Ash.Changeset.for_create(:create, %{name: "Weight", unit: "kg"}, actor: user)
      |> Ash.create!()

    Ash.Seed.seed!(Measurement, %{
      user_id: user.id,
      metric_id: metric.id,
      value: Decimal.new("90"),
      recorded_at: DateTime.utc_now()
    })

    {:ok, view, html} = live(conn, ~p"/meals/settings")
    assert html =~ "Save your profile below"

    html =
      view
      |> form("#nutrition-profile-form",
        form: %{
          height_cm: "180",
          birthdate: "1991-03-15",
          sex: "male",
          activity_level: "moderate",
          goal: "cut",
          goal_rate_kcal_per_day: "400",
          weight_metric_id: metric.id,
          protein_g_per_kg: "2.0",
          fat_pct: "25"
        }
      )
      |> render_submit()

    assert html =~ "Meal settings saved"
    assert html =~ "BMR"
    assert html =~ "overrides applied"

    profile = Meals.profile_for(user)
    assert profile.sex == :male
    assert profile.weight_metric_id == metric.id
  end

  test "manual overrides alone produce targets without a weight metric", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/meals/settings")

    html =
      view
      |> form("#nutrition-profile-form",
        form: %{
          override_kcal: "2400",
          override_protein_g: "180",
          override_fat_g: "65",
          override_carbs_g: "270"
        }
      )
      |> render_submit()

    assert html =~ "2400 kcal"
    assert html =~ "overrides applied"

    profile = Meals.profile_for(user)
    assert profile.override_kcal == 2400
  end
end
