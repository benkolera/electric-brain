defmodule ElectricbrainWeb.IngredientLive.IndexTest do
  use ElectricbrainWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Electricbrain.Meals.Ingredient

  setup %{conn: conn} do
    user = create_user!()
    {:ok, conn: log_in_user(conn, user), user: user}
  end

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

  test "blank query shows only own custom ingredients", %{conn: conn, user: user} do
    seed_global!("Chicken breast, grilled", "F001")

    Ingredient
    |> Ash.Changeset.for_create(
      :create,
      %{
        name: "My protein powder",
        kcal_per_100g: "380",
        protein_g_per_100g: "80",
        fat_g_per_100g: "5",
        carbs_g_per_100g: "6",
        fibre_g_per_100g: "0"
      },
      actor: user
    )
    |> Ash.create!()

    {:ok, _view, html} = live(conn, ~p"/ingredients")

    assert html =~ "My protein powder"
    refute html =~ "Chicken breast, grilled"
  end

  test "search surfaces AFCD rows with a badge", %{conn: conn} do
    seed_global!("Chicken breast, grilled", "F001")

    {:ok, view, _html} = live(conn, ~p"/ingredients")

    html =
      view
      |> element("form[phx-change=search]")
      |> render_change(%{"q" => "chicken"})

    assert html =~ "Chicken breast, grilled"
    assert html =~ "AFCD"
  end

  test "creates a custom ingredient through the form", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/ingredients")

    view |> element("button[phx-click=toggle_create]") |> render_click()

    html =
      view
      |> form("#ingredient-form",
        form: %{
          name: "Chobani plain Greek yogurt",
          kcal_per_100g: "59",
          protein_g_per_100g: "10.3",
          fat_g_per_100g: "0.4",
          carbs_g_per_100g: "3.6",
          fibre_g_per_100g: "0"
        }
      )
      |> render_submit()

    assert html =~ "Chobani plain Greek yogurt"
    assert html =~ "Custom"
  end
end
