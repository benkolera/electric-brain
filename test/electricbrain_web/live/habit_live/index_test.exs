defmodule ElectricbrainWeb.HabitLive.IndexTest do
  use ElectricbrainWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  require Ash.Query

  alias Electricbrain.Categories
  alias Electricbrain.Categories.Category
  alias Electricbrain.Habits.Completion
  alias Electricbrain.Habits.Habit
  alias Electricbrain.Habits.RitualStep
  alias Electricbrain.Habits.StepCheck

  setup %{conn: conn} do
    user = create_user!()
    :ok = Categories.seed_defaults_for(user)
    {:ok, conn: log_in_user(conn, user), user: user}
  end

  test "renders the empty state when there are no habits", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/habits")
    assert html =~ "Habits"
    assert html =~ "No habits yet"
  end

  test "creating a habit shows it in the list with progress 0/N", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/habits")

    health =
      Category
      |> Ash.Query.filter(name == "Health")
      |> Ash.read_one!(actor: user)

    view |> element("button[phx-click=open_create]") |> render_click()

    view
    |> element("input[phx-keyup=filter_categories]")
    |> render_keyup(%{"value" => "Health"})

    view
    |> element(~s|li[phx-click=select_category][phx-value-id="#{health.id}"]|)
    |> render_click()

    html =
      view
      |> form("#habit-form", %{
        "form" => %{
          "title" => "Exercise",
          "min_count" => "3",
          "period" => "week",
          "fixed_schedule" => "false"
        }
      })
      |> render_submit()

    assert html =~ "Exercise"
    assert html =~ "0 / 3"

    assert [habit] = Ash.read!(Habit, actor: user)
    assert habit.category_id == health.id
    assert habit.min_count == 3
    assert habit.period == :week
  end

  test "marking a habit done increments the progress", %{conn: conn, user: user} do
    habit = create_habit!(user, min_count: 2, period: :week)

    {:ok, view, _html} = live(conn, ~p"/habits")

    html =
      view
      |> element(~s|button[phx-click=mark_done][phx-value-id="#{habit.id}"]|)
      |> render_click()

    assert html =~ "1 / 2"

    html =
      view
      |> element(~s|button[phx-click=mark_done][phx-value-id="#{habit.id}"]|)
      |> render_click()

    assert html =~ "2 / 2"
    assert length(Ash.read!(Completion, actor: user)) == 2
  end

  test "deleting a habit removes it and its completions", %{conn: conn, user: user} do
    habit = create_habit!(user)

    Completion
    |> Ash.Changeset.for_create(:create, %{habit_id: habit.id}, actor: user)
    |> Ash.create!()

    {:ok, view, _html} = live(conn, ~p"/habits")

    html =
      view
      |> element(~s|button[phx-click=delete][phx-value-id="#{habit.id}"]|)
      |> render_click()

    assert html =~ "No habits yet"
    assert Ash.read!(Habit, actor: user) == []
    assert Ash.read!(Completion, actor: user) == []
  end

  test "ritual habit: mark_done opens modal and ticks persist across reload", %{
    conn: conn,
    user: user
  } do
    habit = create_habit!(user, min_count: 1, period: :week)

    step =
      RitualStep
      |> Ash.Changeset.for_create(
        :create,
        %{habit_id: habit.id, title: "brush teeth"},
        actor: user
      )
      |> Ash.create!()

    {:ok, view, _html} = live(conn, ~p"/habits")

    html =
      view
      |> element(~s|button[phx-click=mark_done][phx-value-id="#{habit.id}"]|)
      |> render_click()

    assert html =~ "brush teeth"
    assert [_] = Ash.read!(Completion, actor: user)

    html =
      view
      |> element(~s|button[phx-click=toggle_step][phx-value-step_id="#{step.id}"]|)
      |> render_click()

    assert [_check] = Ash.read!(StepCheck, actor: user)
    refute html =~ "brush teeth"

    [completion] = Ash.read!(Completion, actor: user)
    refute is_nil(completion.completed_at)
    assert html =~ "1 / 1"
  end

  test "ritual habit: partial tick leaves completion in progress", %{conn: conn, user: user} do
    habit = create_habit!(user, min_count: 1, period: :week)

    step_a =
      RitualStep
      |> Ash.Changeset.for_create(
        :create,
        %{habit_id: habit.id, title: "screens off"},
        actor: user
      )
      |> Ash.create!()

    RitualStep
    |> Ash.Changeset.for_create(
      :create,
      %{habit_id: habit.id, title: "brush teeth"},
      actor: user
    )
    |> Ash.create!()

    {:ok, view, _html} = live(conn, ~p"/habits")

    view
    |> element(~s|button[phx-click=mark_done][phx-value-id="#{habit.id}"]|)
    |> render_click()

    view
    |> element(~s|button[phx-click=toggle_step][phx-value-step_id="#{step_a.id}"]|)
    |> render_click()

    [completion] = Ash.read!(Completion, actor: user)
    assert is_nil(completion.completed_at)
    assert [_check] = Ash.read!(StepCheck, actor: user)
  end

  defp create_habit!(user, opts \\ []) do
    attrs =
      Map.merge(
        %{
          title: "Exercise",
          category_id: Categories.inbox_for(user).id,
          min_count: 1,
          period: :week
        },
        Map.new(opts)
      )

    Habit
    |> Ash.Changeset.for_create(:create, attrs, actor: user)
    |> Ash.create!()
  end
end
