defmodule Electricbrain.Meals.PlanningTest do
  use Electricbrain.DataCase, async: true

  require Ash.Query

  alias Electricbrain.Meals.Ingredient
  alias Electricbrain.Meals.NutritionProfile
  alias Electricbrain.Meals.Planning
  alias Electricbrain.Meals.Recipe

  # A Monday.
  @week_start ~D[2026-07-13]

  defp create_profile!(user, attrs \\ %{}) do
    NutritionProfile
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(
        %{
          override_kcal: 2400,
          override_protein_g: 180,
          override_fat_g: 67,
          override_carbs_g: 270
        },
        attrs
      ),
      actor: user
    )
    |> Ash.create!()
  end

  defp ingredient!(user, name, kcal, protein) do
    Ingredient
    |> Ash.Changeset.for_create(
      :create,
      %{
        name: name,
        kcal_per_100g: to_string(kcal),
        protein_g_per_100g: to_string(protein),
        fat_g_per_100g: "10",
        carbs_g_per_100g: "20",
        fibre_g_per_100g: "0"
      },
      actor: user
    )
    |> Ash.create!()
  end

  defp recipe!(user, name, slot, ingredient) do
    Recipe
    |> Ash.Changeset.for_create(
      :create,
      %{
        name: name,
        slot_type: slot,
        servings: 1,
        recipe_ingredients: [%{ingredient_id: ingredient.id, quantity_g: 100}]
      },
      actor: user
    )
    |> Ash.create!()
  end

  defp seed_library!(user) do
    base = ingredient!(user, "Base food", 450, 35)
    shake_base = ingredient!(user, "Whey", 380, 80)

    %{
      b1: recipe!(user, "Oats bowl", :breakfast, base),
      b2: recipe!(user, "Egg wraps", :breakfast, base),
      m1: recipe!(user, "Chicken rice", :main, base),
      m2: recipe!(user, "Beef bowls", :main, base),
      s1: recipe!(user, "Cottage cups", :snack, base),
      k1: recipe!(user, "Whey shake", :shake, shake_base)
    }
  end

  test "generate_week errors without a profile" do
    user = create_user!()
    assert {:error, :no_profile} = Planning.generate_week(user, @week_start)
  end

  test "generate_week errors when targets are incomplete" do
    user = create_user!()
    create_profile!(user, %{override_kcal: nil})

    assert {:error, :incomplete_targets} = Planning.generate_week(user, @week_start)
  end

  test "generate_week snapshots targets and persists planned meals" do
    user = create_user!()
    create_profile!(user)
    seed_library!(user)

    assert {:ok, week} = Planning.generate_week(user, @week_start)

    assert week.status == :draft
    assert week.target_kcal == 2400
    assert week.target_protein_g == 180

    slots = Enum.frequencies_by(week.planned_meals, & &1.slot)
    assert slots.breakfast == 5
    assert slots.lunch == 5
    assert slots.dinner == 5
    assert slots.snack == 5
  end

  test "regenerating replaces the draft without duplicating" do
    user = create_user!()
    create_profile!(user)
    seed_library!(user)

    {:ok, first} = Planning.generate_week(user, @week_start)
    {:ok, second} = Planning.generate_week(user, @week_start)

    refute first.id == second.id
    assert [_only] = Ash.read!(Electricbrain.Meals.MealWeek, actor: user)
  end

  test "a confirmed week cannot be regenerated" do
    user = create_user!()
    create_profile!(user)
    seed_library!(user)

    {:ok, week} = Planning.generate_week(user, @week_start)
    Planning.confirm_week(user, week)

    assert {:error, :week_confirmed} = Planning.generate_week(user, @week_start)
  end

  test "last week's picks rotate out when the pool allows" do
    user = create_user!()
    create_profile!(user)
    library = seed_library!(user)

    # Third breakfast so exclusion has somewhere to go.
    extra = ingredient!(user, "Extra food", 400, 30)
    recipe!(user, "Yogurt parfait", :breakfast, extra)

    {:ok, prev} = Planning.generate_week(user, Date.add(@week_start, -7))

    prev_breakfasts =
      prev.planned_meals |> Enum.filter(&(&1.slot == :breakfast)) |> MapSet.new(& &1.recipe_id)

    {:ok, this} = Planning.generate_week(user, @week_start)

    this_breakfasts =
      this.planned_meals |> Enum.filter(&(&1.slot == :breakfast)) |> MapSet.new(& &1.recipe_id)

    assert MapSet.disjoint?(prev_breakfasts, this_breakfasts) or
             MapSet.size(MapSet.intersection(prev_breakfasts, this_breakfasts)) < 2

    _ = library
  end

  test "default_week_start flips to next week from Saturday" do
    user = create_user!()

    # Fri 2026-07-10 12:00 Brisbane
    friday = ~U[2026-07-10 02:00:00Z]
    # Sat 2026-07-11 12:00 Brisbane
    saturday = ~U[2026-07-11 02:00:00Z]

    user = %{user | timezone: "Australia/Brisbane"}

    assert Planning.default_week_start(user, friday) == ~D[2026-07-06]
    assert Planning.default_week_start(user, saturday) == ~D[2026-07-13]
  end
end
