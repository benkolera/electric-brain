defmodule ElectricbrainWeb.TodoLive.ScheduleTest do
  use ElectricbrainWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Electricbrain.Categories
  alias Electricbrain.Todos.Availability
  alias Electricbrain.Todos.Todo

  setup %{conn: conn} do
    user = create_user!()
    :ok = Categories.seed_defaults_for(user)
    inbox = Categories.inbox_for(user)

    todo =
      Todo
      |> Ash.Changeset.for_create(
        :create,
        %{title: "Walk dog", category_id: inbox.id},
        actor: user
      )
      |> Ash.create!()

    {:ok, conn: log_in_user(conn, user), user: user, todo: todo}
  end

  test "saves duration and buffer fields", %{conn: conn, user: user, todo: todo} do
    {:ok, view, _html} = live(conn, ~p"/todos/#{todo.id}/schedule")

    view
    |> form("#timing-form", %{
      "form" => %{
        "duration_minutes" => "30",
        "buffer_before_minutes" => "10",
        "buffer_after_minutes" => "5"
      }
    })
    |> render_submit()

    updated = Ash.get!(Todo, todo.id, actor: user)
    assert updated.duration_minutes == 30
    assert updated.buffer_before_minutes == 10
    assert updated.buffer_after_minutes == 5
  end

  test "adds an availability window", %{conn: conn, user: user, todo: todo} do
    {:ok, view, _html} = live(conn, ~p"/todos/#{todo.id}/schedule")

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

  test "deletes an availability window", %{conn: conn, user: user, todo: todo} do
    availability =
      Availability
      |> Ash.Changeset.for_create(
        :create,
        %{
          todo_id: todo.id,
          day_of_week: 1,
          start_time: ~T[09:00:00],
          end_time: ~T[10:00:00]
        },
        actor: user
      )
      |> Ash.create!()

    {:ok, view, _html} = live(conn, ~p"/todos/#{todo.id}/schedule")

    html =
      view
      |> element(~s|button[phx-click=delete_availability][phx-value-id="#{availability.id}"]|)
      |> render_click()

    assert html =~ "No windows set"
    assert Ash.read!(Availability, actor: user) == []
  end
end
