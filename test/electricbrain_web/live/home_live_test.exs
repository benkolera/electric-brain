defmodule ElectricbrainWeb.HomeLiveTest do
  use ElectricbrainWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Electricbrain.Categories
  alias Electricbrain.Habits.Habit

  setup %{conn: conn} do
    user = create_user!()
    :ok = Categories.seed_defaults_for(user)
    {:ok, conn: log_in_user(conn, user), user: user}
  end

  test "shows the welcome block for a brand-new user", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Welcome to Trellis"
    assert html =~ "Get set up"
    assert html =~ "Edit the category tree"
  end

  test "hides the welcome block once a habit exists", %{conn: conn, user: user} do
    inbox = Categories.inbox_for(user)

    Habit
    |> Ash.Changeset.for_create(
      :create,
      %{title: "Exercise", category_id: inbox.id, min_count: 1, period: :day},
      actor: user
    )
    |> Ash.create!()

    {:ok, _view, html} = live(conn, ~p"/")

    refute html =~ "Welcome to Electric Brain"
  end
end
