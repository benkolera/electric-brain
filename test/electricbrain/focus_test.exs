defmodule Electricbrain.FocusTest do
  use Electricbrain.DataCase, async: true

  require Ash.Query

  alias Electricbrain.Focus.Session
  alias Electricbrain.Todos.Todo

  setup do
    user = create_user!()
    :ok = Electricbrain.Categories.seed_defaults_for(user)

    category =
      Electricbrain.Categories.Category
      |> Ash.Query.limit(1)
      |> Ash.read!(actor: user)
      |> hd()

    {:ok, user: user, category: category}
  end

  defp start_session!(user, attrs \\ %{}) do
    Session
    |> Ash.Changeset.for_create(:start, attrs, actor: user)
    |> Ash.create!()
  end

  describe ":start" do
    test "creates a running session with defaults snapshotted", %{user: user} do
      session = start_session!(user)

      assert session.status == :running
      assert session.duration_minutes == 25
      assert session.break_minutes == 5
      assert session.started_at
      refute session.break_started_at
      refute session.ended_at
    end

    test "accepts custom durations", %{user: user} do
      session = start_session!(user, %{duration_minutes: 50, break_minutes: 10})

      assert session.duration_minutes == 50
      assert session.break_minutes == 10
    end

    test "accepts an exclusive target", %{user: user, category: category} do
      session = start_session!(user, %{category_id: category.id})
      assert session.category_id == category.id
      assert session.todo_id == nil
    end

    test "rejects two targets at once", %{user: user, category: category} do
      todo =
        Ash.Seed.seed!(Todo, %{
          title: "x",
          priority: :medium,
          status: :pending,
          category_id: category.id,
          user_id: user.id
        })

      assert {:error, _} =
               Session
               |> Ash.Changeset.for_create(
                 :start,
                 %{todo_id: todo.id, category_id: category.id},
                 actor: user
               )
               |> Ash.create()
    end

    test "rejects another user's todo as a target", %{user: user, category: category} do
      other = create_user!()

      foreign_todo =
        Ash.Seed.seed!(Todo, %{
          title: "x",
          priority: :medium,
          status: :pending,
          category_id: category.id,
          user_id: other.id
        })

      assert {:error, _} =
               Session
               |> Ash.Changeset.for_create(:start, %{todo_id: foreign_todo.id}, actor: user)
               |> Ash.create()
    end

    test "rejects a second active session for the same user", %{user: user} do
      _ = start_session!(user)

      assert {:error, _} =
               Session
               |> Ash.Changeset.for_create(:start, %{}, actor: user)
               |> Ash.create()
    end

    test "allows a new session after the previous one completes", %{user: user} do
      first = start_session!(user)

      first
      |> Ash.Changeset.for_update(:complete, %{}, actor: user)
      |> Ash.update!()

      second = start_session!(user)
      assert second.id != first.id
      assert second.status == :running
    end
  end

  describe "transitions" do
    test ":start_break flips status and stamps break_started_at", %{user: user} do
      session = start_session!(user)

      updated =
        session
        |> Ash.Changeset.for_update(:start_break, %{}, actor: user)
        |> Ash.update!()

      assert updated.status == :on_break
      assert updated.break_started_at
    end

    test ":complete sets ended_at and ends the session", %{user: user} do
      session = start_session!(user)

      updated =
        session
        |> Ash.Changeset.for_update(:complete, %{}, actor: user)
        |> Ash.update!()

      assert updated.status == :completed
      assert updated.ended_at
    end

    test ":abandon ends from running", %{user: user} do
      session = start_session!(user)

      updated =
        session
        |> Ash.Changeset.for_update(:abandon, %{}, actor: user)
        |> Ash.update!()

      assert updated.status == :abandoned
      assert updated.ended_at
    end
  end

  describe "ownership" do
    test "another user cannot read your sessions", %{user: user} do
      _ = start_session!(user)
      other = create_user!()

      rows =
        Session
        |> Ash.Query.filter(user_id == ^user.id)
        |> Ash.read!(actor: other)

      assert rows == []
    end
  end

  describe "User focus defaults" do
    test "default 25/5 and :set_focus_defaults updates them", %{user: user} do
      assert user.focus_work_minutes == 25
      assert user.focus_break_minutes == 5

      updated =
        user
        |> Ash.Changeset.for_update(:set_focus_defaults, %{
          focus_work_minutes: 45,
          focus_break_minutes: 10
        })
        |> Ash.update!(actor: user)

      assert updated.focus_work_minutes == 45
      assert updated.focus_break_minutes == 10
    end
  end
end
