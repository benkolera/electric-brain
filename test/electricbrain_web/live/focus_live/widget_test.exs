defmodule ElectricbrainWeb.FocusLive.WidgetTest do
  # async: false because Focus.Scheduler is a singleton GenServer.
  use ElectricbrainWeb.ConnCase, async: false

  @moduletag capture_log: true

  import Phoenix.LiveViewTest

  alias Electricbrain.Focus.Scheduler

  setup %{conn: conn} do
    user = create_user!()
    :ok = Electricbrain.Categories.seed_defaults_for(user)

    Ecto.Adapters.SQL.Sandbox.allow(
      Electricbrain.Repo,
      self(),
      Process.whereis(Scheduler)
    )

    Scheduler.clear_all_timers()

    {:ok, conn: log_in_user(conn, user), user: user}
  end

  test "idle widget shows the 'Focus' pill", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Focus"
    assert html =~ "focus-widget"
  end

  test "opening the dialog reveals the tab pills and minute inputs", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html = element(view, "#focus-widget button", "Focus") |> render_click()

    assert html =~ "Start focus"
    assert html =~ "Nothing"
    assert html =~ "Todo"
    assert html =~ "Habit"
    assert html =~ "Time block"
    assert html =~ "Category"
    assert html =~ "Work (min)"
    assert html =~ "Break (min)"
  end

  test "starting a freestanding session swaps the widget to the running card", %{
    conn: conn,
    user: user
  } do
    Phoenix.PubSub.subscribe(Electricbrain.PubSub, Scheduler.topic(user.id))

    {:ok, view, _html} = live(conn, ~p"/")
    render_click(element(view, "#focus-widget button", "Focus"))
    render_click(element(view, "#focus-widget button", "Start"))

    assert_receive {:focus_session, %{status: :running}}, 500

    # Flush the LV's mailbox so its hook handles the same broadcast.
    _ = :sys.get_state(view.pid)

    html = render(view)
    assert html =~ "Focusing"
    assert html =~ "End"
  end
end
