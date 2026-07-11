defmodule ElectricbrainWeb.MealLive.IndexTest do
  use ElectricbrainWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  require Ash.Query

  alias Electricbrain.Meals.Ingredient
  alias Electricbrain.Meals.NutritionProfile
  alias Electricbrain.Meals.Planning
  alias Electricbrain.Meals.Recipe

  @week "2026-07-13"

  setup %{conn: conn} do
    user = create_user!()
    {:ok, conn: log_in_user(conn, user), user: user}
  end

  defp create_profile!(user) do
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
  end

  defp seed_library!(user) do
    base =
      Ingredient
      |> Ash.Changeset.for_create(
        :create,
        %{
          name: "Base food",
          kcal_per_100g: "450",
          protein_g_per_100g: "35",
          fat_g_per_100g: "10",
          carbs_g_per_100g: "20",
          fibre_g_per_100g: "0"
        },
        actor: user
      )
      |> Ash.create!()

    for {name, slot} <- [
          {"Oats bowl", :breakfast},
          {"Egg wraps", :breakfast},
          {"Chicken rice", :main},
          {"Beef bowls", :main},
          {"Cottage cups", :snack},
          {"Whey shake", :shake}
        ] do
      Recipe
      |> Ash.Changeset.for_create(
        :create,
        %{
          name: name,
          slot_type: slot,
          servings: 1,
          recipe_ingredients: [%{ingredient_id: base.id, quantity_g: 100}]
        },
        actor: user
      )
      |> Ash.create!()
    end
  end

  test "prompts for a profile before generating", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/meals?week=#{@week}")

    assert html =~ "Set up nutrition profile"
  end

  test "generate -> review -> swap -> confirm flow", %{conn: conn, user: user} do
    create_profile!(user)
    seed_library!(user)

    {:ok, view, html} = live(conn, ~p"/meals?week=#{@week}")
    assert html =~ "Generate week"

    html = view |> element("button", "Generate week") |> render_click()
    assert html =~ "Draft"
    assert html =~ "Oats bowl"
    assert html =~ "vs target"
    assert html =~ "2400 kcal"

    # Swap Monday's lunch to the other main.
    view
    |> element("button[phx-value-date='2026-07-13'][phx-value-slot='lunch']")
    |> render_click()

    week = Planning.week_for(user, ~D[2026-07-13])

    monday_lunch =
      Enum.find(week.planned_meals, &(&1.date == ~D[2026-07-13] and &1.slot == :lunch))

    other_main =
      Recipe
      |> Ash.read!(actor: user)
      |> Enum.find(&(&1.slot_type == :main and &1.id != monday_lunch.recipe_id))

    html =
      view
      |> element("form[phx-submit=swap]")
      |> render_submit(%{"recipe_id" => other_main.id, "servings" => "2"})

    assert html =~ "×2"

    html = view |> element("button", "Confirm week") |> render_click()
    assert html =~ "Confirmed"
    refute html =~ "Regenerate"

    week = Planning.week_for(user, ~D[2026-07-13])
    assert week.status == :confirmed

    swapped = Enum.find(week.planned_meals, &(&1.date == ~D[2026-07-13] and &1.slot == :lunch))
    assert swapped.recipe_id == other_main.id
    assert Decimal.equal?(swapped.servings, Decimal.new(2))
  end
end
