defmodule Electricbrain.Meals do
  use Ash.Domain,
    otp_app: :electricbrain

  resources do
    resource Electricbrain.Meals.Ingredient
    resource Electricbrain.Meals.Recipe
    resource Electricbrain.Meals.RecipeIngredient
    resource Electricbrain.Meals.NutritionProfile
  end

  require Ash.Query

  @doc "The user's nutrition profile, or nil if they haven't set one up."
  def profile_for(user) do
    Electricbrain.Meals.NutritionProfile
    |> Ash.Query.filter(user_id == ^user.id)
    |> Ash.read_one!(actor: user)
  end
end
