defmodule ElectricbrainWeb.TrainingLive.SettingsTest do
  use ElectricbrainWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Electricbrain.Training

  setup %{conn: conn} do
    user = create_user!()
    {:ok, conn: log_in_user(conn, user), user: user}
  end

  test "saves schedule settings", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/training/settings")

    view
    |> element("form[phx-submit=save_settings]")
    |> render_submit(%{
      "training_days" => ["2", "4", "6"],
      "reminder_time" => "05:45",
      "default_rest_seconds" => "150"
    })

    settings = Training.settings_for(user)
    assert settings.training_days == [2, 4, 6]
    assert settings.reminder_time == ~T[05:45:00]
    assert settings.default_rest_seconds == 150
  end

  test "saves an exercise's weight (the starting-weights prompt) and params", %{
    conn: conn,
    user: user
  } do
    {:ok, view, html} = live(conn, ~p"/training/settings")
    assert html =~ "Back squat"

    squat = Enum.find(Training.exercises_for(user), &(&1.name == "Back squat"))

    view
    |> element("form[phx-submit=save_exercise] input[value='#{squat.id}']")
    |> then(fn _ -> view end)
    |> element("form[phx-submit=save_exercise]:has(input[value='#{squat.id}'])")
    |> render_submit(%{
      "exercise_id" => squat.id,
      "current_weight_kg" => "82.5",
      "current_reps" => "",
      "increment_kg" => "2.5",
      "rep_ceiling" => "",
      "rest_seconds" => "240"
    })

    squat = Enum.find(Training.exercises_for(user), &(&1.name == "Back squat"))
    assert Decimal.equal?(squat.state.current_weight_kg, Decimal.new("82.5"))
    assert squat.rest_seconds == 240
  end

  test "template editor removes and edits slots", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/training/settings")

    [a, _b] = Training.templates_for(user)
    squat = Enum.find(Training.exercises_for(user), &(&1.name == "Back squat"))

    # Trim template A from 5 slots to 2 (removing index 2 three times).
    for _ <- 1..3 do
      view
      |> element(
        "form:has(input[value='#{a.id}']) button[phx-click=remove_slot][phx-value-index='2']"
      )
      |> render_click()
    end

    [a, _b] = Training.templates_for(user)
    assert length(a.slots) == 2

    # Edit the remaining two: squat 3×5 + a 2-set accessory. Submitted
    # params merge over the rendered form fields.
    view
    |> element("form[phx-submit=save_template]:has(input[value='#{a.id}'])")
    |> render_submit(%{
      "template_id" => a.id,
      "slots" => %{
        "0" => %{"kind" => "fixed", "exercise_id" => squat.id, "sets" => "3", "reps" => "5"},
        "1" => %{"kind" => "accessory", "exercise_id" => "", "sets" => "2", "reps" => ""}
      }
    })

    [a, _b] = Training.templates_for(user)

    assert [%{kind: :fixed, sets: 3, reps: 5}, %{kind: :accessory, sets: 2}] =
             Enum.map(a.slots, &Map.take(&1, [:kind, :sets, :reps]))
  end
end
