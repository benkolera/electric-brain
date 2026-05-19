defmodule ElectricbrainWeb.PlannerLive.IndexTest do
  use ElectricbrainWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  require Ash.Query

  alias Electricbrain.Categories
  alias Electricbrain.Habits.Habit
  alias Electricbrain.Planner.Entry
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

    habit =
      Habit
      |> Ash.Changeset.for_create(
        :create,
        %{title: "Exercise", category_id: inbox.id, min_count: 3, period: :week},
        actor: user
      )
      |> Ash.create!()

    {:ok, conn: log_in_user(conn, user), user: user, todo: todo, habit: habit}
  end

  test "shows the empty pool", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/plan")
    assert html =~ "This week pool"
    assert html =~ "No floating items"
  end

  test "adding a todo creates a floating entry", %{conn: conn, user: user, todo: todo} do
    {:ok, view, _html} = live(conn, ~p"/plan")

    view |> element("button", "Add") |> render_click()

    html =
      view
      |> element(
        ~s|button[phx-click=add_to_week][phx-value-kind=todo][phx-value-id="#{todo.id}"]|
      )
      |> render_click()

    assert html =~ "Walk dog"
    assert [entry] = Ash.read!(Entry, actor: user)
    assert entry.todo_id == todo.id
  end

  test "scheduling a floating entry sets planned_at", %{conn: conn, user: user, todo: todo} do
    entry =
      Entry
      |> Ash.Changeset.for_create(
        :create,
        %{todo_id: todo.id, week_start: today_monday(user)},
        actor: user
      )
      |> Ash.create!()

    {:ok, view, _html} = live(conn, ~p"/plan")

    monday = today_monday(user)
    dt_local = "#{Date.to_iso8601(monday)}T18:00"

    view
    |> form("#schedule-form-#{entry.id}", %{
      "entry_id" => entry.id,
      "datetime" => dt_local
    })
    |> render_submit()

    assert %{planned_at: planned_at} = Ash.get!(Entry, entry.id, actor: user)
    refute is_nil(planned_at)
  end

  test "unschedule clears planned_at", %{conn: conn, user: user, todo: todo} do
    entry =
      Entry
      |> Ash.Changeset.for_create(
        :create,
        %{
          todo_id: todo.id,
          week_start: today_monday(user),
          planned_at: ~U[2026-05-20 18:00:00.000000Z]
        },
        actor: user
      )
      |> Ash.create!()

    {:ok, view, _html} = live(conn, ~p"/plan")

    view
    |> element(~s|button[phx-click=unschedule_entry][phx-value-id="#{entry.id}"]|)
    |> render_click()

    assert Ash.get!(Entry, entry.id, actor: user).planned_at == nil
  end

  test "remove deletes the entry", %{conn: conn, user: user, todo: todo} do
    entry =
      Entry
      |> Ash.Changeset.for_create(
        :create,
        %{todo_id: todo.id, week_start: today_monday(user)},
        actor: user
      )
      |> Ash.create!()

    {:ok, view, _html} = live(conn, ~p"/plan")

    view
    |> element(~s|button[phx-click=remove_entry][phx-value-id="#{entry.id}"]|)
    |> render_click()

    assert Ash.read!(Entry, actor: user) == []
  end

  test "shows per-category soft totals for scheduled entries", %{
    conn: conn,
    user: user,
    habit: habit
  } do
    # Move the habit to Health and give it a duration
    health =
      Electricbrain.Categories.Category
      |> Ash.Query.filter(name == "Health")
      |> Ash.read_one!(actor: user)

    habit
    |> Ash.Changeset.for_update(
      :update,
      %{category_id: health.id, duration_minutes: 45},
      actor: user
    )
    |> Ash.update!()

    Entry
    |> Ash.Changeset.for_create(
      :create,
      %{
        habit_id: habit.id,
        week_start: today_monday(user),
        planned_at: ~U[2026-05-20 18:00:00.000000Z]
      },
      actor: user
    )
    |> Ash.create!()

    {:ok, _view, html} = live(conn, ~p"/plan")

    assert html =~ "Planned this week"
    assert html =~ "Health"
    assert html =~ "45m"
  end

  test "prev/next week navigation changes the visible entries", %{
    conn: conn,
    user: user,
    todo: todo
  } do
    monday = today_monday(user)
    next_monday = Date.add(monday, 7)

    Entry
    |> Ash.Changeset.for_create(
      :create,
      %{todo_id: todo.id, week_start: next_monday},
      actor: user
    )
    |> Ash.create!()

    {:ok, view, html} = live(conn, ~p"/plan")
    refute html =~ "Walk dog"

    html = view |> element("button", "Next") |> render_click()
    assert html =~ "Walk dog"
  end

  defp today_monday(user) do
    local = DateTime.shift_zone!(DateTime.utc_now(), user.timezone)
    date = DateTime.to_date(local)
    days_back = Date.day_of_week(date) - 1
    Date.add(date, -days_back)
  end
end
