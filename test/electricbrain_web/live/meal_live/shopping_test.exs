defmodule ElectricbrainWeb.MealLive.ShoppingTest do
  use ElectricbrainWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Electricbrain.Meals.Ingredient
  alias Electricbrain.Meals.NutritionProfile
  alias Electricbrain.Meals.Planning
  alias Electricbrain.Meals.Recipe

  @week "2026-07-13"

  setup %{conn: conn} do
    user = create_user!()
    {:ok, conn: log_in_user(conn, user), user: user}
  end

  defp confirm_week!(user) do
    NutritionProfile
    |> Ash.Changeset.for_create(
      :create,
      %{
        override_kcal: 2400,
        override_protein_g: 180,
        override_fat_g: 67,
        override_carbs_g: 270,
        max_shakes_per_day: 0
      },
      actor: user
    )
    |> Ash.create!()

    chicken =
      Ingredient
      |> Ash.Changeset.for_create(
        :create,
        %{
          name: "Chicken breast",
          kcal_per_100g: "165",
          protein_g_per_100g: "31",
          fat_g_per_100g: "3.6",
          carbs_g_per_100g: "0",
          fibre_g_per_100g: "0"
        },
        actor: user
      )
      |> Ash.create!()

    Recipe
    |> Ash.Changeset.for_create(
      :create,
      %{
        name: "Chicken rice",
        slot_type: :main,
        servings: 4,
        recipe_ingredients: [%{ingredient_id: chicken.id, quantity_g: 600}]
      },
      actor: user
    )
    |> Ash.create!()

    {:ok, week} = Planning.generate_week(user, ~D[2026-07-13])
    Planning.confirm_week(user, week)
  end

  test "prompts when no confirmed week exists", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/meals/shopping?week=#{@week}")

    assert html =~ "No confirmed meal plan yet"
  end

  test "lists aggregated items and toggles the trolley state", %{conn: conn, user: user} do
    confirm_week!(user)

    {:ok, view, html} = live(conn, ~p"/meals/shopping?week=#{@week}")

    assert html =~ "Chicken breast"
    assert html =~ "0/1 in the trolley"

    html = view |> element("input[type=checkbox]") |> render_click()

    assert html =~ "1/1 in the trolley"
    assert html =~ "line-through"
  end
end
