defmodule Electricbrain.Meals do
  use Ash.Domain,
    otp_app: :electricbrain

  resources do
    resource Electricbrain.Meals.Ingredient
    resource Electricbrain.Meals.Recipe
    resource Electricbrain.Meals.RecipeIngredient
  end
end
