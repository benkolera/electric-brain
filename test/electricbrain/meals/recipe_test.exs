defmodule Electricbrain.Meals.RecipeTest do
  use Electricbrain.DataCase, async: true

  require Ash.Query

  alias Electricbrain.Meals.Ingredient
  alias Electricbrain.Meals.Recipe
  alias Electricbrain.Meals.RecipeIngredient

  defp seed_global!(name, code) do
    Ash.Seed.seed!(Ingredient, %{
      name: name,
      source: :afcd,
      afcd_code: code,
      kcal_per_100g: Decimal.new("165"),
      protein_g_per_100g: Decimal.new("31"),
      fat_g_per_100g: Decimal.new("3.6"),
      carbs_g_per_100g: Decimal.new("0"),
      fibre_g_per_100g: Decimal.new("0")
    })
  end

  defp create_recipe!(user, attrs) do
    Recipe
    |> Ash.Changeset.for_create(:create, attrs, actor: user)
    |> Ash.create!()
  end

  describe "create with recipe_ingredients" do
    test "creates the recipe and its ingredient lines, denormalising user" do
      user = create_user!()
      chicken = seed_global!("Chicken breast", "F001")

      recipe =
        create_recipe!(user, %{
          name: "Grilled chicken",
          slot_type: :main,
          servings: 4,
          recipe_ingredients: [%{ingredient_id: chicken.id, quantity_g: 600}]
        })

      assert recipe.user_id == user.id

      [line] = Ash.load!(recipe, [:recipe_ingredients], actor: user).recipe_ingredients
      assert line.ingredient_id == chicken.id
      assert line.user_id == user.id
      assert Decimal.equal?(line.quantity_g, Decimal.new(600))
    end

    test "update replaces, updates, and removes lines by ingredient identity" do
      user = create_user!()
      chicken = seed_global!("Chicken breast", "F001")
      rice = seed_global!("Rice, white", "F002")

      recipe =
        create_recipe!(user, %{
          name: "Chicken and rice",
          slot_type: :main,
          servings: 4,
          recipe_ingredients: [
            %{ingredient_id: chicken.id, quantity_g: 600},
            %{ingredient_id: rice.id, quantity_g: 400}
          ]
        })

      # Change chicken quantity, drop the rice.
      updated =
        recipe
        |> Ash.Changeset.for_update(
          :update,
          %{recipe_ingredients: [%{ingredient_id: chicken.id, quantity_g: 700}]},
          actor: user
        )
        |> Ash.update!()

      [line] = Ash.load!(updated, [:recipe_ingredients], actor: user).recipe_ingredients
      assert line.ingredient_id == chicken.id
      assert Decimal.equal?(line.quantity_g, Decimal.new(700))
    end

    test "cannot reference another user's custom ingredient" do
      user = create_user!()
      other = create_user!()

      theirs =
        Ingredient
        |> Ash.Changeset.for_create(
          :create,
          %{
            name: "Their powder",
            kcal_per_100g: "380",
            protein_g_per_100g: "80",
            fat_g_per_100g: "5",
            carbs_g_per_100g: "6",
            fibre_g_per_100g: "0"
          },
          actor: other
        )
        |> Ash.create!()

      assert {:error, _} =
               Recipe
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   name: "Sneaky shake",
                   slot_type: :shake,
                   recipe_ingredients: [%{ingredient_id: theirs.id, quantity_g: 30}]
                 },
                 actor: user
               )
               |> Ash.create()
    end
  end

  describe "policies" do
    test "recipes are invisible to other users" do
      user = create_user!()
      other = create_user!()
      create_recipe!(user, %{name: "Mine", slot_type: :main})

      assert [] = Ash.read!(Recipe, actor: other)
      assert [] = Ash.read!(RecipeIngredient, actor: other)
    end
  end

  describe "ingredient deletion" do
    test "an ingredient used by a recipe cannot be deleted" do
      user = create_user!()

      yogurt =
        Ingredient
        |> Ash.Changeset.for_create(
          :create,
          %{
            name: "Greek yogurt",
            kcal_per_100g: "59",
            protein_g_per_100g: "10.3",
            fat_g_per_100g: "0.4",
            carbs_g_per_100g: "3.6",
            fibre_g_per_100g: "0"
          },
          actor: user
        )
        |> Ash.create!()

      create_recipe!(user, %{
        name: "Yogurt bowl",
        slot_type: :breakfast,
        recipe_ingredients: [%{ingredient_id: yogurt.id, quantity_g: 250}]
      })

      assert {:error, _} = Ash.destroy(yogurt, actor: user)
    end
  end
end
