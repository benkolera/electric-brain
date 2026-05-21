defmodule ElectricbrainWeb.TimeBlockLive.IndexTest do
  use ElectricbrainWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Electricbrain.Categories
  alias Electricbrain.TimeBlocks.TimeBlock

  setup %{conn: conn} do
    user = create_user!()
    :ok = Categories.seed_defaults_for(user)
    {:ok, conn: log_in_user(conn, user), user: user}
  end

  test "save creates a time block in the default inbox category", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/time-blocks")

    view |> element("button[phx-click=toggle_create]") |> render_click()

    html =
      view
      |> form("#create-time-block", %{"form" => %{"title" => "Sleep"}})
      |> render_submit()

    assert html =~ "Sleep"
    assert [block] = Ash.read!(TimeBlock, actor: user)
    assert block.title == "Sleep"
    assert block.category_id == Categories.inbox_for(user).id
  end
end
