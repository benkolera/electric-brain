defmodule ElectricbrainWeb.TrainingLive.SessionTest do
  use ElectricbrainWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Electricbrain.Training

  setup %{conn: conn} do
    user = create_user!()
    {:ok, conn: log_in_user(conn, user), user: user}
  end

  defp start_workout!(user) do
    :ok = Training.ensure_setup!(user)
    {:ok, workout} = Training.start_workout!(user)
    workout
  end

  test "redirects to /training when nothing is active", %{conn: conn, user: user} do
    :ok = Training.ensure_setup!(user)

    assert {:error, {:live_redirect, %{to: "/training"}}} = live(conn, ~p"/training/session")
  end

  test "tapping a set logs it at target reps and arms the rest countdown", %{
    conn: conn,
    user: user
  } do
    workout = start_workout!(user)
    squat_set = Enum.find(workout.sets, &(&1.exercise_name == "Back squat"))

    {:ok, view, html} = live(conn, ~p"/training/session")
    assert html =~ "Session A"
    assert html =~ "Back squat — 5×5 @ 20 kg"

    html =
      view
      |> element("button[phx-click=toggle_set][phx-value-id='#{squat_set.id}']")
      |> render_click()

    assert html =~ "1/#{length(workout.sets)} sets"
    assert html =~ "Rest"
    assert html =~ "FocusCountdown"

    reloaded = Training.active_workout(user)
    logged = Enum.find(reloaded.sets, &(&1.id == squat_set.id))
    assert logged.actual_reps == 5
    assert logged.completed_at
  end

  test "decrement records fewer reps; toggle again unlogs", %{conn: conn, user: user} do
    workout = start_workout!(user)
    set = hd(workout.sets)

    {:ok, view, _html} = live(conn, ~p"/training/session")

    view |> element("button[phx-click=toggle_set][phx-value-id='#{set.id}']") |> render_click()
    view |> element("button[phx-click=decrement_set][phx-value-id='#{set.id}']") |> render_click()

    logged = Training.active_workout(user).sets |> Enum.find(&(&1.id == set.id))
    assert logged.actual_reps == set.target_reps - 1

    view |> element("button[phx-click=toggle_set][phx-value-id='#{set.id}']") |> render_click()
    unlogged = Training.active_workout(user).sets |> Enum.find(&(&1.id == set.id))
    assert is_nil(unlogged.actual_reps)
  end

  test "finish completes the workout and applies progression", %{conn: conn, user: user} do
    workout = start_workout!(user)

    Enum.each(workout.sets, fn set ->
      set
      |> Ash.Changeset.for_update(:log, %{actual_reps: set.target_reps}, actor: user)
      |> Ash.update!()
    end)

    {:ok, view, _html} = live(conn, ~p"/training/session")

    view |> element("button", "Finish workout") |> render_click()
    assert_redirect(view, "/training")

    assert is_nil(Training.active_workout(user))

    squat = Enum.find(Training.exercises_for(user), &(&1.name == "Back squat"))
    assert Decimal.equal?(squat.state.current_weight_kg, Decimal.new("22.5"))
  end

  test "abandon applies nothing", %{conn: conn, user: user} do
    _workout = start_workout!(user)

    {:ok, view, _html} = live(conn, ~p"/training/session")
    view |> element("button", "Abandon") |> render_click()
    assert_redirect(view, "/training")

    squat = Enum.find(Training.exercises_for(user), &(&1.name == "Back squat"))
    assert Decimal.equal?(squat.state.current_weight_kg, Decimal.new(20))
  end
end
