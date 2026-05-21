defmodule ElectricbrainWeb.MomentLive.IndexTest do
  use ElectricbrainWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  require Ash.Query

  alias Electricbrain.Categories
  alias Electricbrain.Moments.Moment

  setup %{conn: conn} do
    user = create_user!()
    :ok = Categories.seed_defaults_for(user)
    inbox = Categories.inbox_for(user)
    {:ok, conn: log_in_user(conn, user), user: user, inbox: inbox}
  end

  test "lists moments newest first and filters by kind", %{conn: conn, user: user, inbox: inbox} do
    {:ok, _} =
      Moment
      |> Ash.Changeset.for_create(
        :create,
        %{kind: :craving, name: "chocolate", intensity: 3, category_id: inbox.id},
        actor: user
      )
      |> Ash.create()

    {:ok, _} =
      Moment
      |> Ash.Changeset.for_create(
        :create,
        %{kind: :feeling, name: "demo nerves", intensity: 4, category_id: inbox.id},
        actor: user
      )
      |> Ash.create()

    {:ok, view, html} = live(conn, ~p"/moments")
    assert html =~ "chocolate"
    assert html =~ "demo nerves"

    html =
      view
      |> element(~s|button[phx-click=filter_kind][phx-value-kind=craving]|)
      |> render_click()

    assert html =~ "chocolate"
    refute html =~ "demo nerves"
  end

  test "creates a moment from the RAIN form", %{conn: conn, user: user, inbox: _inbox} do
    {:ok, view, _html} = live(conn, ~p"/moments/new")

    view
    |> form("#moment-form", %{
      "form" => %{
        "name" => "chocolate",
        "intensity" => "4",
        "recognize" => "tightness",
        "allow" => "",
        "investigate" => "",
        "nurture" => ""
      }
    })
    |> render_submit()

    assert [m] = Ash.read!(Moment, actor: user)
    assert m.name == "chocolate"
    assert m.kind == :craving
    assert m.intensity == 4
    assert m.recognize == "tightness"
    refute is_nil(m.category_id)
  end

  test "kind chip switches the saved kind", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/moments/new")

    view
    |> element(~s|button[phx-click=pick_kind][phx-value-kind=feeling]|)
    |> render_click()

    view
    |> form("#moment-form", %{
      "form" => %{"name" => "demo nerves", "intensity" => "3"}
    })
    |> render_submit()

    assert [m] = Ash.read!(Moment, actor: user)
    assert m.kind == :feeling
  end
end
