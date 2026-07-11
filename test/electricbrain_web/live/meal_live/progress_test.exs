defmodule ElectricbrainWeb.MealLive.ProgressTest do
  use ElectricbrainWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Electricbrain.Meals
  alias Electricbrain.Meals.NutritionProfile
  alias Electricbrain.Metrics.Measurement
  alias Electricbrain.Metrics.Metric

  setup %{conn: conn} do
    user = create_user!()

    profile =
      NutritionProfile
      |> Ash.Changeset.for_create(
        :create,
        %{
          override_kcal: 2400,
          override_protein_g: 180,
          override_fat_g: 67,
          override_carbs_g: 270
        },
        actor: user
      )
      |> Ash.create!()

    {:ok, conn: log_in_user(conn, user), user: user, profile: profile}
  end

  test "picking metrics in settings surfaces the panel on /meals", %{
    conn: conn,
    user: user,
    profile: profile
  } do
    metric =
      Metric
      |> Ash.Changeset.for_create(:create, %{name: "Weight", unit: "kg"}, actor: user)
      |> Ash.create!()

    Ash.Seed.seed!(Measurement, %{
      user_id: user.id,
      metric_id: metric.id,
      value: Decimal.new("90.4"),
      recorded_at: DateTime.utc_now()
    })

    # Pick it on the settings page.
    {:ok, view, _html} = live(conn, ~p"/meals/settings")

    html =
      view
      |> element("form[phx-submit=save_progress_metrics]")
      |> render_submit(%{"metric_ids" => [metric.id]})

    assert html =~ "Progress metrics saved"
    assert [link] = Meals.feedback_metrics(user, profile)
    assert link.metric_id == metric.id

    # Panel shows on /meals with the latest value.
    {:ok, _view, html} = live(conn, ~p"/meals")
    assert html =~ "Weight"
    assert html =~ "90.4"
  end

  test "no panel without linked metrics", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/meals")

    refute html =~ "no data"
  end
end
