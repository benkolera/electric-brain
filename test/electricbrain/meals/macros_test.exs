defmodule Electricbrain.Meals.MacrosTest do
  use ExUnit.Case, async: true

  alias Electricbrain.Meals.Macros

  defp ingredient(kcal, protein, fat, carbs, fibre \\ 0) do
    %{
      kcal_per_100g: Decimal.new(to_string(kcal)),
      protein_g_per_100g: Decimal.new(to_string(protein)),
      fat_g_per_100g: Decimal.new(to_string(fat)),
      carbs_g_per_100g: Decimal.new(to_string(carbs)),
      fibre_g_per_100g: Decimal.new(to_string(fibre))
    }
  end

  test "for_quantity scales per-100g values by grams" do
    chicken = ingredient(165, 31, "3.6", 0)

    macros = Macros.for_quantity(chicken, Decimal.new(200))

    assert_in_delta macros.kcal, 330.0, 0.001
    assert_in_delta macros.protein_g, 62.0, 0.001
    assert_in_delta macros.fat_g, 7.2, 0.001
    assert_in_delta macros.carbs_g, 0.0, 0.001
  end

  test "per_serving sums ingredient lines and divides by servings" do
    chicken = ingredient(165, 31, "3.6", 0)
    rice = ingredient(130, "2.7", "0.3", 28)

    recipe = %{
      servings: Decimal.new(4),
      recipe_ingredients: [
        %{ingredient: chicken, quantity_g: Decimal.new(600)},
        %{ingredient: rice, quantity_g: Decimal.new(400)}
      ]
    }

    macros = Macros.per_serving(recipe)

    # (165*6 + 130*4) / 4 = (990 + 520) / 4
    assert_in_delta macros.kcal, 377.5, 0.001
    # (31*6 + 2.7*4) / 4 = (186 + 10.8) / 4
    assert_in_delta macros.protein_g, 49.2, 0.001
    # (28*4) / 4
    assert_in_delta macros.carbs_g, 28.0, 0.001
  end

  test "per_serving of an empty recipe is zero" do
    recipe = %{servings: Decimal.new(2), recipe_ingredients: []}

    assert Macros.per_serving(recipe) == Macros.zero()
  end

  test "sum and scale compose" do
    a = %{kcal: 100.0, protein_g: 10.0, fat_g: 5.0, carbs_g: 8.0, fibre_g: 2.0}
    b = %{kcal: 50.0, protein_g: 5.0, fat_g: 2.5, carbs_g: 4.0, fibre_g: 1.0}

    summed = Macros.sum([a, b])
    doubled = Macros.scale(summed, 2.0)

    assert_in_delta summed.kcal, 150.0, 0.001
    assert_in_delta doubled.protein_g, 30.0, 0.001
  end
end
