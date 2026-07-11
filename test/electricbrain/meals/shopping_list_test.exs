defmodule Electricbrain.Meals.ShoppingListTest do
  use Electricbrain.DataCase, async: true

  require Ash.Query

  alias Electricbrain.Meals.Ingredient
  alias Electricbrain.Meals.NutritionProfile
  alias Electricbrain.Meals.PlannedMeal
  alias Electricbrain.Meals.Planning
  alias Electricbrain.Meals.Recipe
  alias Electricbrain.Meals.ShoppingListItem

  @week_start ~D[2026-07-13]

  defp ingredient!(user, name) do
    Ingredient
    |> Ash.Changeset.for_create(
      :create,
      %{
        name: name,
        kcal_per_100g: "450",
        protein_g_per_100g: "35",
        fat_g_per_100g: "10",
        carbs_g_per_100g: "20",
        fibre_g_per_100g: "0"
      },
      actor: user
    )
    |> Ash.create!()
  end

  defp recipe!(user, name, slot, lines, servings) do
    Recipe
    |> Ash.Changeset.for_create(
      :create,
      %{
        name: name,
        slot_type: slot,
        servings: servings,
        recipe_ingredients:
          Enum.map(lines, fn {ing, grams} -> %{ingredient_id: ing.id, quantity_g: grams} end)
      },
      actor: user
    )
    |> Ash.create!()
  end

  defp setup_confirmed_week! do
    user = create_user!()

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

    chicken = ingredient!(user, "Chicken breast")
    rice = ingredient!(user, "Rice")
    oats = ingredient!(user, "Oats")

    # One breakfast, one main, one snack — thin library, repeats fill the week.
    recipe!(user, "Oats bowl", :breakfast, [{oats, 120}], 1)
    recipe!(user, "Chicken rice", :main, [{chicken, 600}, {rice, 400}], 4)
    recipe!(user, "Chicken cups", :snack, [{chicken, 100}], 1)

    {:ok, week} = Planning.generate_week(user, @week_start)
    week = Planning.confirm_week(user, week)

    {user, week, %{chicken: chicken, rice: rice, oats: oats}}
  end

  test "aggregates grams across meals: quantity x servings / batch servings" do
    {user, week, %{chicken: chicken, rice: rice, oats: oats}} = setup_confirmed_week!()

    items = Planning.shopping_list(user, week)
    by_ingredient = Map.new(items, &{&1.ingredient_id, &1})

    week = Ash.load!(week, [planned_meals: [recipe: [:recipe_ingredients]]], actor: user)

    # Hand-compute expected totals from the persisted plan.
    expected =
      week.planned_meals
      |> Enum.flat_map(fn meal ->
        factor = Decimal.to_float(meal.servings) / Decimal.to_float(meal.recipe.servings)

        Enum.map(
          meal.recipe.recipe_ingredients,
          &{&1.ingredient_id, Decimal.to_float(&1.quantity_g) * factor}
        )
      end)
      |> Enum.reduce(%{}, fn {id, g}, acc -> Map.update(acc, id, g, &(&1 + g)) end)

    for ing <- [chicken, rice, oats] do
      assert_in_delta Decimal.to_float(by_ingredient[ing.id].total_quantity_g),
                      Float.round(expected[ing.id], 1),
                      0.05
    end
  end

  test "rebuild preserves checked_at and updates quantities" do
    {user, week, %{oats: oats}} = setup_confirmed_week!()

    [oats_item] =
      Planning.shopping_list(user, week) |> Enum.filter(&(&1.ingredient_id == oats.id))

    checked =
      oats_item
      |> Ash.Changeset.for_update(:toggle_checked, %{}, actor: user)
      |> Ash.update!()

    assert checked.checked_at

    # Double every breakfast's servings, then rebuild.
    week_loaded = Ash.load!(week, :planned_meals, actor: user)

    week_loaded.planned_meals
    |> Enum.filter(&(&1.slot == :breakfast))
    |> Enum.each(fn meal ->
      meal
      |> Ash.Changeset.for_update(
        :swap,
        %{recipe_id: meal.recipe_id, servings: Decimal.mult(meal.servings, 2)},
        actor: user
      )
      |> Ash.update!()
    end)

    :ok = Planning.rebuild_shopping_list(user, week)

    [rebuilt] = Planning.shopping_list(user, week) |> Enum.filter(&(&1.ingredient_id == oats.id))

    assert rebuilt.checked_at
    assert Decimal.compare(rebuilt.total_quantity_g, oats_item.total_quantity_g) == :gt
  end

  test "rebuild deletes rows for ingredients no longer in the plan" do
    {user, week, %{oats: oats}} = setup_confirmed_week!()

    # Remove all breakfasts (the only oats source).
    week_loaded = Ash.load!(week, :planned_meals, actor: user)

    week_loaded.planned_meals
    |> Enum.filter(&(&1.slot == :breakfast))
    |> Enum.each(&Ash.destroy!(&1, actor: user))

    :ok = Planning.rebuild_shopping_list(user, week)

    assert Planning.shopping_list(user, week)
           |> Enum.filter(&(&1.ingredient_id == oats.id)) == []
  end

  test "items belong to the user and are invisible to others" do
    {_user, week, _ingredients} = setup_confirmed_week!()
    other = create_user!()

    assert [] = Ash.read!(ShoppingListItem, actor: other)
    assert [] = Ash.read!(PlannedMeal, actor: other)
    _ = week
  end
end
