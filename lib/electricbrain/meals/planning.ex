defmodule Electricbrain.Meals.Planning do
  @moduledoc """
  Orchestrates weekly plan generation: loads the profile, resolves
  targets (computed from the latest weight + overrides), feeds the
  recipe library and last week's picks to the pure `Generator`, and
  persists the result as a draft `MealWeek` + `PlannedMeal` rows
  (replacing any existing draft for that week).
  """

  require Ash.Query

  alias Electricbrain.Meals
  alias Electricbrain.Meals.Generator
  alias Electricbrain.Meals.Macros
  alias Electricbrain.Meals.MealWeek
  alias Electricbrain.Meals.PlannedMeal
  alias Electricbrain.Meals.Recipe
  alias Electricbrain.Meals.ShoppingListItem
  alias Electricbrain.Meals.Targets
  alias Electricbrain.Meals.Weight

  @doc """
  Resolved daily targets for the user, or an error naming what's
  missing: `:no_profile` | `:incomplete_targets`.
  """
  def resolved_targets(user) do
    case Meals.profile_for(user) do
      nil -> {:error, :no_profile}
      profile -> resolved_targets(user, profile)
    end
  end

  def resolved_targets(user, profile) do
    case Targets.resolve(profile, computed_targets(user, profile)) do
      {:ok, resolved} -> {:ok, resolved}
      {:error, :incomplete_targets} -> {:error, :incomplete_targets}
    end
  end

  @doc """
  The computed (pre-override) targets, or nil when there's no weight
  or the profile can't produce a TDEE. Uses the Oura observed TDEE
  when enough data exists (see `Oura.Sync.observed_tdee/2`).
  """
  def computed_targets(user, profile) do
    today = user.timezone |> DateTime.now!() |> DateTime.to_date()

    observed =
      case Electricbrain.Oura.Sync.observed_tdee(user) do
        {:ok, tdee} -> tdee
        :none -> nil
      end

    with {:ok, %{kg: kg}} <- Weight.latest(user, profile),
         {:ok, computed} <-
           Targets.compute(profile, Decimal.to_float(kg), today, observed_tdee: observed) do
      computed
    else
      _ -> nil
    end
  end

  @doc """
  Generates (or regenerates) the draft week starting at `week_start`
  (a Monday, user-local). Returns `{:ok, meal_week}` or
  `{:error, :no_profile | :incomplete_targets | :week_confirmed}`.
  """
  def generate_week(user, week_start) do
    with {:ok, profile} <- fetch_profile(user),
         {:ok, targets} <- resolved_targets(user, profile),
         :ok <- ensure_not_confirmed(user, week_start) do
      %{planned: planned, warnings: warnings} =
        Generator.generate(%{
          recipes: generator_recipes(user),
          last_week_recipe_ids: previous_week_recipe_ids(user, week_start),
          targets: targets,
          week_start: week_start,
          max_shakes_per_day: profile.max_shakes_per_day
        })

      replace_draft(user, week_start, targets, warnings, planned)
    end
  end

  defp fetch_profile(user) do
    case Meals.profile_for(user) do
      nil -> {:error, :no_profile}
      profile -> {:ok, profile}
    end
  end

  defp ensure_not_confirmed(user, week_start) do
    case week_for(user, week_start) do
      %MealWeek{status: :confirmed} -> {:error, :week_confirmed}
      _ -> :ok
    end
  end

  @doc "The MealWeek row for a week, or nil."
  def week_for(user, week_start) do
    MealWeek
    |> Ash.Query.filter(week_start == ^week_start)
    |> Ash.Query.load(planned_meals: [recipe: [recipe_ingredients: [:ingredient]]])
    |> Ash.read_one!(actor: user)
  end

  @doc "Locks the week in and builds (or rebuilds) its shopping list."
  def confirm_week(user, meal_week) do
    confirmed =
      meal_week
      |> Ash.Changeset.for_update(:confirm, %{}, actor: user)
      |> Ash.update!()

    rebuild_shopping_list(user, confirmed)
    confirmed
  end

  @doc """
  Aggregates the week's planned meals into shopping list rows: per
  ingredient, Σ quantity_g × planned servings ÷ recipe batch servings.
  Upserts by ingredient (preserving checked_at), deletes rows for
  ingredients no longer in the plan.
  """
  def rebuild_shopping_list(user, meal_week) do
    meal_week =
      Ash.load!(meal_week, [planned_meals: [recipe: [:recipe_ingredients]]], actor: user)

    totals =
      meal_week.planned_meals
      |> Enum.flat_map(fn meal ->
        batch_servings = Decimal.to_float(meal.recipe.servings)
        factor = Decimal.to_float(meal.servings) / max(batch_servings, 1.0e-9)

        Enum.map(meal.recipe.recipe_ingredients, fn line ->
          {line.ingredient_id, Decimal.to_float(line.quantity_g) * factor}
        end)
      end)
      |> Enum.reduce(%{}, fn {ingredient_id, grams}, acc ->
        Map.update(acc, ingredient_id, grams, &(&1 + grams))
      end)

    Enum.each(totals, fn {ingredient_id, grams} ->
      ShoppingListItem
      |> Ash.Changeset.for_create(
        :upsert,
        %{
          meal_week_id: meal_week.id,
          ingredient_id: ingredient_id,
          total_quantity_g: grams |> Float.round(1) |> Decimal.from_float()
        },
        actor: user
      )
      |> Ash.create!()
    end)

    ShoppingListItem
    |> Ash.Query.filter(meal_week_id == ^meal_week.id)
    |> Ash.read!(actor: user)
    |> Enum.reject(&Map.has_key?(totals, &1.ingredient_id))
    |> Enum.each(&Ash.destroy!(&1, actor: user))

    :ok
  end

  @doc "The week's shopping list, ingredient-loaded, sorted by name."
  def shopping_list(user, meal_week) do
    ShoppingListItem
    |> Ash.Query.filter(meal_week_id == ^meal_week.id)
    |> Ash.Query.load(:ingredient)
    |> Ash.read!(actor: user)
    |> Enum.sort_by(& &1.ingredient.name)
  end

  defp generator_recipes(user) do
    Recipe
    |> Ash.Query.load(recipe_ingredients: [:ingredient])
    |> Ash.read!(actor: user)
    |> Enum.map(fn recipe ->
      %{
        id: recipe.id,
        name: recipe.name,
        slot_type: recipe.slot_type,
        per_serving: Macros.per_serving(recipe)
      }
    end)
  end

  defp previous_week_recipe_ids(user, week_start) do
    prev_start = Date.add(week_start, -7)

    case MealWeek
         |> Ash.Query.filter(week_start == ^prev_start)
         |> Ash.Query.load(:planned_meals)
         |> Ash.read_one!(actor: user) do
      nil -> MapSet.new()
      week -> MapSet.new(week.planned_meals, & &1.recipe_id)
    end
  end

  defp replace_draft(user, week_start, targets, warnings, planned) do
    case week_for(user, week_start) do
      %MealWeek{status: :draft} = existing -> Ash.destroy!(existing, actor: user)
      _ -> :ok
    end

    meal_week =
      MealWeek
      |> Ash.Changeset.for_create(
        :create,
        %{
          week_start: week_start,
          target_kcal: targets.kcal,
          target_protein_g: targets.protein_g,
          target_fat_g: targets.fat_g,
          target_carbs_g: targets.carbs_g,
          warnings: warnings
        },
        actor: user
      )
      |> Ash.create!()

    planned
    |> Enum.map(fn row ->
      %{
        meal_week_id: meal_week.id,
        recipe_id: row.recipe_id,
        date: row.date,
        slot: row.slot,
        servings: Decimal.from_float(row.servings)
      }
    end)
    |> Ash.bulk_create!(PlannedMeal, :create,
      actor: user,
      stop_on_error?: true,
      return_errors?: true
    )

    {:ok, week_for(user, week_start)}
  end

  @doc """
  The Monday (user-local) of the week the meal pages should default
  to: next week from Saturday onward — the Saturday shop and Sunday
  prep serve the week ahead.
  """
  def default_week_start(user, now \\ DateTime.utc_now()) do
    local = DateTime.shift_zone!(now, user.timezone)
    date = DateTime.to_date(local)
    monday = Date.add(date, -(Date.day_of_week(date) - 1))

    if Date.day_of_week(date) >= 6, do: Date.add(monday, 7), else: monday
  end
end
