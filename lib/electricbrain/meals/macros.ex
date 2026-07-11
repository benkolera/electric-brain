defmodule Electricbrain.Meals.Macros do
  @moduledoc """
  Pure macro arithmetic shared by the recipe form preview, the weekly
  plan generator, day totals, and the shopping list. Works in floats;
  callers convert to Decimal only at persistence boundaries.

  A macros map is `%{kcal, protein_g, fat_g, carbs_g, fibre_g}` —
  all floats.
  """

  @type t :: %{
          kcal: float(),
          protein_g: float(),
          fat_g: float(),
          carbs_g: float(),
          fibre_g: float()
        }

  @keys [:kcal, :protein_g, :fat_g, :carbs_g, :fibre_g]

  def zero, do: Map.new(@keys, &{&1, 0.0})

  @doc """
  Macros for `quantity_g` grams of an ingredient (per-100g fields).
  """
  def for_quantity(ingredient, quantity_g) do
    factor = to_float(quantity_g) / 100.0

    %{
      kcal: to_float(ingredient.kcal_per_100g) * factor,
      protein_g: to_float(ingredient.protein_g_per_100g) * factor,
      fat_g: to_float(ingredient.fat_g_per_100g) * factor,
      carbs_g: to_float(ingredient.carbs_g_per_100g) * factor,
      fibre_g: to_float(ingredient.fibre_g_per_100g) * factor
    }
  end

  @doc """
  Per-serving macros for a recipe. Requires `recipe_ingredients` with
  their `ingredient` loaded.
  """
  def per_serving(recipe) do
    servings = max(to_float(recipe.servings), 1.0e-9)

    recipe.recipe_ingredients
    |> Enum.map(&for_quantity(&1.ingredient, &1.quantity_g))
    |> sum()
    |> scale(1.0 / servings)
  end

  def sum(macros_list) do
    Enum.reduce(macros_list, zero(), fn macros, acc ->
      Map.new(@keys, &{&1, acc[&1] + macros[&1]})
    end)
  end

  def scale(macros, factor) do
    Map.new(@keys, &{&1, macros[&1] * factor})
  end

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(f) when is_float(f), do: f
  defp to_float(i) when is_integer(i), do: i * 1.0
end
