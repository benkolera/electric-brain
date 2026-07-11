defmodule Electricbrain.Meals.IngredientTest do
  use Electricbrain.DataCase, async: true

  require Ash.Query

  alias Electricbrain.Meals.Ingredient

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

  defp create_custom!(user, name) do
    Ingredient
    |> Ash.Changeset.for_create(
      :create,
      %{
        name: name,
        kcal_per_100g: "59",
        protein_g_per_100g: "10.3",
        fat_g_per_100g: "0.4",
        carbs_g_per_100g: "3.6",
        fibre_g_per_100g: "0"
      },
      actor: user
    )
    |> Ash.create!()
  end

  describe "create" do
    test "creates a custom ingredient owned by the actor" do
      user = create_user!()

      ingredient = create_custom!(user, "Chobani plain Greek yogurt")

      assert ingredient.user_id == user.id
      assert ingredient.source == :custom
      assert is_nil(ingredient.afcd_code)
    end
  end

  describe "read" do
    test "global rows are readable by any signed-in user" do
      user = create_user!()
      seed_global!("Chicken breast, grilled", "F001")

      names =
        Ingredient
        |> Ash.read!(actor: user)
        |> Enum.map(& &1.name)

      assert "Chicken breast, grilled" in names
    end

    test "another user's custom ingredients are invisible" do
      user = create_user!()
      other = create_user!()
      create_custom!(other, "Other's secret yogurt")

      assert [] = Ash.read!(Ingredient, actor: user)
    end

    test "search matches globals and own rows case-insensitively" do
      user = create_user!()
      other = create_user!()
      seed_global!("Chicken breast, grilled", "F001")
      seed_global!("Broccoli, raw", "F002")
      create_custom!(user, "Chicken-style seasoning")
      create_custom!(other, "Chicken stock, other user's")

      names =
        Ingredient
        |> Ash.Query.for_read(:search, %{q: "CHICKEN"}, actor: user)
        |> Ash.read!()
        |> Enum.map(& &1.name)

      assert Enum.sort(names) == ["Chicken breast, grilled", "Chicken-style seasoning"]
    end
  end

  describe "update / destroy" do
    test "user can update and destroy their own ingredient" do
      user = create_user!()
      ingredient = create_custom!(user, "Chobani plain Greek yogurt")

      updated =
        ingredient
        |> Ash.Changeset.for_update(:update, %{kcal_per_100g: "61"}, actor: user)
        |> Ash.update!()

      assert Decimal.equal?(updated.kcal_per_100g, Decimal.new("61"))
      assert :ok = Ash.destroy(updated, actor: user)
    end

    test "seeded global rows cannot be updated or destroyed by a user" do
      user = create_user!()
      global = seed_global!("Chicken breast, grilled", "F001")

      assert {:error, %Ash.Error.Forbidden{}} =
               global
               |> Ash.Changeset.for_update(:update, %{kcal_per_100g: "1"}, actor: user)
               |> Ash.update()

      assert {:error, %Ash.Error.Forbidden{}} = Ash.destroy(global, actor: user)
    end
  end

  describe "seed_upsert" do
    test "is forbidden for a normal actor" do
      user = create_user!()

      assert {:error, %Ash.Error.Forbidden{}} =
               Ingredient
               |> Ash.Changeset.for_create(
                 :seed_upsert,
                 %{
                   name: "Sneaky global",
                   source: :afcd,
                   afcd_code: "F999",
                   kcal_per_100g: "1",
                   protein_g_per_100g: "1",
                   fat_g_per_100g: "1",
                   carbs_g_per_100g: "1",
                   fibre_g_per_100g: "1"
                 },
                 actor: user
               )
               |> Ash.create()
    end
  end
end
