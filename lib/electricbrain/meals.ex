defmodule Electricbrain.Meals do
  use Ash.Domain,
    otp_app: :electricbrain

  resources do
    resource Electricbrain.Meals.Ingredient
    resource Electricbrain.Meals.Recipe
    resource Electricbrain.Meals.RecipeIngredient
    resource Electricbrain.Meals.NutritionProfile
    resource Electricbrain.Meals.MealWeek
    resource Electricbrain.Meals.PlannedMeal
    resource Electricbrain.Meals.ShoppingListItem
    resource Electricbrain.Meals.ProfileMetric
  end

  require Ash.Query

  @doc "The user's nutrition profile, or nil if they haven't set one up."
  def profile_for(user) do
    Electricbrain.Meals.NutritionProfile
    |> Ash.Query.filter(user_id == ^user.id)
    |> Ash.read_one!(actor: user)
  end

  @doc "The profile's feedback-metric links in display order, metric loaded."
  def feedback_metrics(user, profile) do
    Electricbrain.Meals.ProfileMetric
    |> Ash.Query.filter(nutrition_profile_id == ^profile.id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.Query.load(:metric)
    |> Ash.read!(actor: user)
  end

  @doc """
  Replaces the profile's feedback-metric links with `metric_ids`, in
  the given order. Links carry no other state, so drop-and-recreate.
  """
  def set_feedback_metrics(user, profile, metric_ids) do
    Electricbrain.Meals.ProfileMetric
    |> Ash.Query.filter(nutrition_profile_id == ^profile.id)
    |> Ash.read!(actor: user)
    |> Enum.each(&Ash.destroy!(&1, actor: user))

    metric_ids
    |> Enum.with_index()
    |> Enum.each(fn {metric_id, position} ->
      Electricbrain.Meals.ProfileMetric
      |> Ash.Changeset.for_create(
        :create,
        %{nutrition_profile_id: profile.id, metric_id: metric_id, position: position},
        actor: user
      )
      |> Ash.create!()
    end)

    :ok
  end
end
