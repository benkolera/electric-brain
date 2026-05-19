defmodule ElectricbrainWeb.TodoLive.IndexTest do
  use ElectricbrainWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  require Ash.Query

  alias Electricbrain.Categories
  alias Electricbrain.Categories.Category
  alias Electricbrain.Todos.Todo

  setup %{conn: conn} do
    user = create_user!()
    :ok = Categories.seed_defaults_for(user)
    {:ok, conn: log_in_user(conn, user), user: user}
  end

  test "mount defaults the category picker to Inbox", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/todos")
    assert html =~ "Inbox"
  end

  test "filtering categories narrows the dropdown", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/todos")

    html =
      view
      |> element("input[phx-keyup=filter_categories]")
      |> render_keyup(%{"value" => "health"})

    assert html =~ "Health"
    refute html =~ ~r/>Work</
  end

  test "selecting a category and submitting creates a todo there", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/todos")

    health =
      Category
      |> Ash.Query.filter(name == "Health")
      |> Ash.read_one!(actor: user)

    # Open the dropdown via filter
    view
    |> element("input[phx-keyup=filter_categories]")
    |> render_keyup(%{"value" => "Health"})

    view
    |> element(~s|li[phx-click=select_category][phx-value-id="#{health.id}"]|)
    |> render_click()

    html =
      view
      |> form("#todo-form", %{"form" => %{"title" => "Stretch", "priority" => "medium"}})
      |> render_submit()

    assert html =~ "Stretch"
    assert [todo] = Ash.read!(Todo, actor: user)
    assert todo.category_id == health.id
  end

  test "category badge renders the breadcrumb on each todo", %{conn: conn, user: user} do
    inbox = Categories.inbox_for(user)

    Todo
    |> Ash.Changeset.for_create(
      :create,
      %{title: "Triage me", category_id: inbox.id},
      actor: user
    )
    |> Ash.create!()

    {:ok, _view, html} = live(conn, ~p"/todos")
    assert html =~ "Triage me"
    assert html =~ "badge"
    assert html =~ "Inbox"
  end

  test "toggle marks a todo done", %{conn: conn, user: user} do
    inbox = Categories.inbox_for(user)

    todo =
      Todo
      |> Ash.Changeset.for_create(
        :create,
        %{title: "Tick me", category_id: inbox.id},
        actor: user
      )
      |> Ash.create!()

    {:ok, view, _html} = live(conn, ~p"/todos")

    view
    |> element(~s|input[type=checkbox][phx-value-id="#{todo.id}"]|)
    |> render_click()

    updated = Ash.get!(Todo, todo.id, actor: user)
    assert updated.status == :done
  end
end
