defmodule ElectricbrainWeb.RecipeLive.FormTest do
  use ElectricbrainWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  require Ash.Query

  alias Electricbrain.Meals.Ingredient
  alias Electricbrain.Meals.Recipe

  setup %{conn: conn} do
    user = create_user!()

    chicken =
      Ash.Seed.seed!(Ingredient, %{
        name: "Chicken breast, grilled",
        source: :afcd,
        afcd_code: "F001",
        kcal_per_100g: Decimal.new("165"),
        protein_g_per_100g: Decimal.new("31"),
        fat_g_per_100g: Decimal.new("3.6"),
        carbs_g_per_100g: Decimal.new("0"),
        fibre_g_per_100g: Decimal.new("0")
      })

    {:ok, conn: log_in_user(conn, user), user: user, chicken: chicken}
  end

  test "creates a recipe with a searched-and-picked ingredient", %{
    conn: conn,
    user: user,
    chicken: chicken
  } do
    {:ok, view, _html} = live(conn, ~p"/recipes/new")

    # Type into the row's search box; the debounced change event carries _target.
    [row_key] = row_keys(view)

    view
    |> element("#recipe-form")
    |> render_change(%{
      "_target" => ["rows", row_key, "search"],
      "form" => %{"name" => "", "servings" => "4"},
      "rows" => %{row_key => %{"search" => "chicken", "quantity_g" => ""}}
    })

    assert render(view) =~ "Chicken breast, grilled"

    view
    |> element("button[phx-click=pick_ingredient]", "Chicken breast, grilled")
    |> render_click()

    # Fill quantity + top-level fields and submit.
    view
    |> element("#recipe-form")
    |> render_change(%{
      "_target" => ["rows", row_key, "quantity_g"],
      "form" => %{"name" => "Grilled chicken", "servings" => "4", "slot_type" => "main"},
      "rows" => %{row_key => %{"quantity_g" => "600"}}
    })

    # Preview reflects 600g chicken over 4 servings: 247.5 kcal, 46.5g protein.
    html = render(view)
    assert html =~ "248 kcal"

    view
    |> form("#recipe-form",
      form: %{name: "Grilled chicken", servings: "4", slot_type: "main"}
    )
    |> render_submit()

    recipe =
      Recipe
      |> Ash.Query.load(recipe_ingredients: [:ingredient])
      |> Ash.read_one!(actor: user)

    assert recipe.name == "Grilled chicken"
    [line] = recipe.recipe_ingredients
    assert line.ingredient_id == chicken.id
    assert Decimal.equal?(line.quantity_g, Decimal.new(600))
  end

  test "quick-adds a custom ingredient and picks it into the row", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/recipes/new")
    [row_key] = row_keys(view)

    view
    |> element("#recipe-form")
    |> render_change(%{
      "_target" => ["rows", row_key, "search"],
      "form" => %{"name" => "", "servings" => "1"},
      "rows" => %{row_key => %{"search" => "Chobani yogurt", "quantity_g" => ""}}
    })

    assert render(view) =~ "New ingredient &quot;Chobani yogurt&quot;"

    view
    |> element("button[phx-click=open_quick_add]")
    |> render_click()

    view
    |> element("#recipe-form")
    |> render_change(%{
      "_target" => ["rows", row_key, "new", "kcal_per_100g"],
      "form" => %{"name" => "", "servings" => "1"},
      "rows" => %{
        row_key => %{
          "quantity_g" => "",
          "new" => %{
            "name" => "Chobani yogurt",
            "kcal_per_100g" => "60",
            "protein_g_per_100g" => "10",
            "fat_g_per_100g" => "0.2",
            "carbs_g_per_100g" => "3.5",
            "fibre_g_per_100g" => ""
          }
        }
      }
    })

    view
    |> element("button[phx-click=create_ingredient]")
    |> render_click()

    # The new ingredient is picked into the row (panel gone, name shown).
    html = render(view)
    assert html =~ "Chobani yogurt"
    refute html =~ "Create &amp; use"

    ingredient =
      Ingredient
      |> Ash.Query.filter(name == "Chobani yogurt")
      |> Ash.read_one!(actor: user)

    assert ingredient.user_id == user.id
    assert ingredient.source == :custom
    assert Decimal.equal?(ingredient.kcal_per_100g, Decimal.new("60"))
    assert Decimal.equal?(ingredient.fibre_g_per_100g, Decimal.new("0"))
  end

  test "quick-add shows errors when macros are missing", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/recipes/new")
    [row_key] = row_keys(view)

    view
    |> element("#recipe-form")
    |> render_change(%{
      "_target" => ["rows", row_key, "search"],
      "form" => %{"name" => "", "servings" => "1"},
      "rows" => %{row_key => %{"search" => "Mystery paste", "quantity_g" => ""}}
    })

    view
    |> element("button[phx-click=open_quick_add]")
    |> render_click()

    view
    |> element("button[phx-click=create_ingredient]")
    |> render_click()

    html = render(view)
    assert html =~ "is required"
    # Panel stays open with the prefilled name for another go.
    assert html =~ "Create &amp; use"
    assert html =~ "Mystery paste"
  end

  test "editing shows existing ingredient lines", %{conn: conn, user: user, chicken: chicken} do
    recipe =
      Recipe
      |> Ash.Changeset.for_create(
        :create,
        %{
          name: "Grilled chicken",
          slot_type: :main,
          servings: 4,
          recipe_ingredients: [%{ingredient_id: chicken.id, quantity_g: 600}]
        },
        actor: user
      )
      |> Ash.create!()

    {:ok, _view, html} = live(conn, ~p"/recipes/#{recipe.id}/edit")

    assert html =~ "Grilled chicken"
    assert html =~ "Chicken breast, grilled"
    assert html =~ "600"
  end

  defp row_keys(view) do
    view
    |> render()
    |> then(&Regex.scan(~r/rows\[(row-\d+)\]\[search\]/, &1))
    |> Enum.map(fn [_, key] -> key end)
    |> Enum.uniq()
  end
end
