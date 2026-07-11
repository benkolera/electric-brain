defmodule ElectricbrainWeb.TrainingLive.IndexTest do
  use ElectricbrainWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Electricbrain.Training

  setup %{conn: conn} do
    user = create_user!()
    {:ok, conn: log_in_user(conn, user), user: user}
  end

  test "first visit seeds the pool and shows the next session", %{conn: conn, user: user} do
    {:ok, _view, html} = live(conn, ~p"/training")

    assert html =~ "Next — Session A"
    assert html =~ "Back squat 5×5 @ 20 kg"
    assert html =~ "Starting weights"

    assert length(Training.exercises_for(user)) == 10
  end

  test "start navigates to the session screen and index shows resume", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/training")

    view |> element("button", "Start workout") |> render_click()
    assert_redirect(view, "/training/session")

    {:ok, _view, html} = live(conn, ~p"/training")
    assert html =~ "Workout in progress"
    assert html =~ "Resume workout"
  end
end
