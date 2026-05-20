defmodule ElectricbrainWeb.HabitLive.EditTest do
  use ElectricbrainWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Electricbrain.Categories
  alias Electricbrain.Habits.Availability
  alias Electricbrain.Habits.Habit
  alias Electricbrain.Habits.RitualStep

  setup %{conn: conn} do
    user = create_user!()
    :ok = Categories.seed_defaults_for(user)
    inbox = Categories.inbox_for(user)

    habit =
      Habit
      |> Ash.Changeset.for_create(
        :create,
        %{title: "Exercise", category_id: inbox.id, min_count: 3, period: :week},
        actor: user
      )
      |> Ash.create!()

    {:ok, conn: log_in_user(conn, user), user: user, habit: habit, inbox: inbox}
  end

  test "saves duration and buffer fields", %{conn: conn, user: user, habit: habit} do
    {:ok, view, _html} = live(conn, ~p"/habits/#{habit.id}/edit")

    view
    |> form("#edit-form", %{
      "form" => %{
        "title" => "Exercise",
        "min_count" => "3",
        "period" => "week",
        "duration_minutes" => "60",
        "buffer_before_minutes" => "15",
        "buffer_after_minutes" => "10",
        "fixed_schedule" => "false"
      }
    })
    |> render_submit()

    updated = Ash.get!(Habit, habit.id, actor: user)
    assert updated.duration_minutes == 60
    assert updated.buffer_before_minutes == 15
    assert updated.buffer_after_minutes == 10
  end

  test "adds an availability window", %{conn: conn, user: user, habit: habit} do
    {:ok, view, _html} = live(conn, ~p"/habits/#{habit.id}/edit")

    html =
      view
      |> form("#availability-form", %{
        "form" => %{
          "day_of_week" => "3",
          "start_time" => "18:00",
          "end_time" => "19:00"
        }
      })
      |> render_submit()

    assert html =~ "Wed"
    assert html =~ "18:00"
    assert [_a] = Ash.read!(Availability, actor: user)
  end

  test "adds a ritual step", %{conn: conn, user: user, habit: habit} do
    {:ok, view, _html} = live(conn, ~p"/habits/#{habit.id}/edit")

    html =
      view
      |> form("#step-form", %{"form" => %{"title" => "brush teeth"}})
      |> render_submit()

    assert html =~ "brush teeth"
    assert [_step] = Ash.read!(RitualStep, actor: user)
  end

  test "deletes a ritual step", %{conn: conn, user: user, habit: habit} do
    step =
      RitualStep
      |> Ash.Changeset.for_create(
        :create,
        %{habit_id: habit.id, title: "screens off"},
        actor: user
      )
      |> Ash.create!()

    {:ok, view, _html} = live(conn, ~p"/habits/#{habit.id}/edit")

    html =
      view
      |> element(~s|button[phx-click=delete_step][phx-value-id="#{step.id}"]|)
      |> render_click()

    assert html =~ "No steps"
    assert Ash.read!(RitualStep, actor: user) == []
  end

  test "deletes an availability window", %{conn: conn, user: user, habit: habit} do
    availability =
      Availability
      |> Ash.Changeset.for_create(
        :create,
        %{
          habit_id: habit.id,
          day_of_week: 1,
          start_time: ~T[09:00:00],
          end_time: ~T[10:00:00]
        },
        actor: user
      )
      |> Ash.create!()

    {:ok, view, _html} = live(conn, ~p"/habits/#{habit.id}/edit")

    html =
      view
      |> element(~s|button[phx-click=delete_availability][phx-value-id="#{availability.id}"]|)
      |> render_click()

    assert html =~ "No windows set"
    assert Ash.read!(Availability, actor: user) == []
  end
end
