defmodule ElectricbrainWeb.HelpLiveTest do
  use ElectricbrainWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    user = create_user!()
    {:ok, conn: log_in_user(conn, user)}
  end

  test "renders the help markdown", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/help")

    assert html =~ "Welcome to Electric Brain"
    assert html =~ "Philosophy"
    assert html =~ "How they link together"
  end
end
