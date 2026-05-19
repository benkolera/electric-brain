defmodule ElectricbrainWeb.CategoryLive.IndexTest do
  use ElectricbrainWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Electricbrain.Categories.Category

  setup %{conn: conn} do
    user = create_user!()
    {:ok, conn: log_in_user(conn, user), user: user}
  end

  test "shows the empty state when there are no categories", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/categories")
    assert html =~ "Categories"
    assert html =~ "No categories yet"
  end

  test "adding a root category renders it in the tree", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/categories")

    view |> element("button", "Add root") |> render_click()

    html =
      view
      |> form("form[phx-submit=save_new]", %{"name" => "Health", "parent_id" => ""})
      |> render_submit()

    assert html =~ "Health"
    assert [%Category{name: "Health"}] = Ash.read!(Category, actor: user)
  end

  test "adding a child category nests it under the parent", %{conn: conn, user: user} do
    parent = create_category!(user, "Health")
    {:ok, view, _html} = live(conn, ~p"/categories")

    view
    |> element(~s|button[phx-click=start_add_child][phx-value-id="#{parent.id}"]|)
    |> render_click()

    html =
      view
      |> form("form[phx-submit=save_new]", %{
        "name" => "Exercise",
        "parent_id" => parent.id
      })
      |> render_submit()

    assert html =~ "Exercise"

    [exercise] = Category |> Ash.read!(actor: user) |> Enum.filter(&(&1.name == "Exercise"))
    assert exercise.parent_id == parent.id
  end

  test "renaming a category updates the display", %{conn: conn, user: user} do
    category = create_category!(user, "Helth")
    {:ok, view, _html} = live(conn, ~p"/categories")

    view |> element("button[phx-click=start_rename]", "Helth") |> render_click()

    html =
      view
      |> form("form[phx-submit=save_rename]", %{
        "category_id" => category.id,
        "name" => "Health"
      })
      |> render_submit()

    assert html =~ "Health"
    refute html =~ "Helth"
  end

  test "deletes a leaf category", %{conn: conn, user: user} do
    category = create_category!(user, "Doomed")
    {:ok, view, _html} = live(conn, ~p"/categories")

    html =
      view
      |> element(~s|button[phx-click=delete][phx-value-id="#{category.id}"]|)
      |> render_click()

    refute html =~ "Doomed"
    assert Ash.read!(Category, actor: user) == []
  end

  test "delete on a category with children shows an error flash", %{conn: conn, user: user} do
    parent = create_category!(user, "Parent")
    _child = create_category!(user, "Child", parent_id: parent.id)
    {:ok, view, _html} = live(conn, ~p"/categories")

    html =
      view
      |> element(~s|button[phx-click=delete][phx-value-id="#{parent.id}"]|)
      |> render_click()

    assert html =~ "Can&#39;t delete a category that still has children"
    assert length(Ash.read!(Category, actor: user)) == 2
  end

  test "neglect bar renders on each tree node", %{conn: conn, user: user} do
    cat = create_category!(user, "Test")

    Electricbrain.Todos.Todo
    |> Ash.Changeset.for_create(
      :create,
      %{title: "Pending", priority: :high, category_id: cat.id},
      actor: user
    )
    |> Ash.create!()

    {:ok, _view, html} = live(conn, ~p"/categories")
    assert html =~ "Neglect signal"
    assert html =~ "high"
  end

  defp create_category!(user, name, opts \\ []) do
    attrs = Map.new([{:name, name} | opts])

    Category
    |> Ash.Changeset.for_create(:create, attrs, actor: user)
    |> Ash.create!()
  end
end
