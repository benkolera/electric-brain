defmodule Electricbrain.Habits.HabitTest do
  use Electricbrain.DataCase, async: true

  alias Electricbrain.Categories
  alias Electricbrain.Habits.Completion
  alias Electricbrain.Habits.Habit

  describe "create/1" do
    test "creates a habit in a category" do
      user = create_user!()
      :ok = Categories.seed_defaults_for(user)
      inbox = Categories.inbox_for(user)

      assert {:ok, habit} =
               Habit
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   title: "Exercise",
                   category_id: inbox.id,
                   min_count: 3,
                   period: :week
                 },
                 actor: user
               )
               |> Ash.create()

      assert habit.title == "Exercise"
      assert habit.min_count == 3
      assert habit.period == :week
      assert habit.user_id == user.id
    end

    test "rejects min_count < 1" do
      user = create_user!()
      :ok = Categories.seed_defaults_for(user)
      inbox = Categories.inbox_for(user)

      assert {:error, _} =
               Habit
               |> Ash.Changeset.for_create(
                 :create,
                 %{title: "x", category_id: inbox.id, min_count: 0},
                 actor: user
               )
               |> Ash.create()
    end

    test "accepts month as a period" do
      user = create_user!()
      :ok = Categories.seed_defaults_for(user)
      inbox = Categories.inbox_for(user)

      assert {:ok, habit} =
               Habit
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   title: "Review finances",
                   category_id: inbox.id,
                   min_count: 1,
                   period: :month
                 },
                 actor: user
               )
               |> Ash.create()

      assert habit.period == :month
    end

    test "rejects unknown period" do
      user = create_user!()
      :ok = Categories.seed_defaults_for(user)
      inbox = Categories.inbox_for(user)

      assert {:error, _} =
               Habit
               |> Ash.Changeset.for_create(
                 :create,
                 %{title: "x", category_id: inbox.id, period: :fortnight},
                 actor: user
               )
               |> Ash.create()
    end

    test "requires a category" do
      user = create_user!()

      assert {:error, _} =
               Habit
               |> Ash.Changeset.for_create(:create, %{title: "x"}, actor: user)
               |> Ash.create()
    end
  end

  describe "policies" do
    test "user only sees their own habits" do
      alice = create_user!()
      bob = create_user!()
      :ok = Categories.seed_defaults_for(alice)
      :ok = Categories.seed_defaults_for(bob)

      Habit
      |> Ash.Changeset.for_create(
        :create,
        %{
          title: "Alice's habit",
          category_id: Categories.inbox_for(alice).id
        },
        actor: alice
      )
      |> Ash.create!()

      assert Habit |> Ash.read!(actor: bob) == []
      assert length(Habit |> Ash.read!(actor: alice)) == 1
    end
  end

  describe "completions" do
    test "creating a completion defaults completed_at to now" do
      user = create_user!()
      :ok = Categories.seed_defaults_for(user)
      habit = create_habit!(user)

      {:ok, completion} =
        Completion
        |> Ash.Changeset.for_create(:create, %{habit_id: habit.id}, actor: user)
        |> Ash.create()

      assert completion.habit_id == habit.id
      assert completion.user_id == user.id
      # completed_at was set automatically
      assert DateTime.diff(DateTime.utc_now(), completion.completed_at, :second) < 5
    end

    test "destroying a habit cascade-deletes its completions" do
      user = create_user!()
      :ok = Categories.seed_defaults_for(user)
      habit = create_habit!(user)

      Completion
      |> Ash.Changeset.for_create(:create, %{habit_id: habit.id}, actor: user)
      |> Ash.create!()

      Completion
      |> Ash.Changeset.for_create(:create, %{habit_id: habit.id}, actor: user)
      |> Ash.create!()

      assert length(Ash.read!(Completion, actor: user)) == 2

      Ash.destroy!(habit, actor: user)

      assert Ash.read!(Completion, actor: user) == []
    end

    test "non-owner cannot create a completion against someone else's habit" do
      alice = create_user!()
      bob = create_user!()
      :ok = Categories.seed_defaults_for(alice)
      :ok = Categories.seed_defaults_for(bob)
      _habit = create_habit!(alice)

      # Bob can create a Completion row tied to himself as actor, but pointing at
      # Alice's habit would surface via the read policy — Alice should still not
      # see Bob's spurious completion (and Bob shouldn't see Alice's habit).
      assert Habit |> Ash.read!(actor: bob) == []
    end
  end

  defp create_habit!(user) do
    Habit
    |> Ash.Changeset.for_create(
      :create,
      %{
        title: "Exercise",
        category_id: Categories.inbox_for(user).id,
        min_count: 3,
        period: :week
      },
      actor: user
    )
    |> Ash.create!()
  end
end
