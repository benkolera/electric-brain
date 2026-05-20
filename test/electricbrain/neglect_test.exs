defmodule Electricbrain.NeglectTest do
  use Electricbrain.DataCase, async: true
  require Ash.Query

  alias Electricbrain.Categories
  alias Electricbrain.Categories.Category
  alias Electricbrain.Habits.Completion
  alias Electricbrain.Habits.Habit
  alias Electricbrain.Neglect
  alias Electricbrain.Todos.Todo

  setup do
    user = create_user!()
    :ok = Categories.seed_defaults_for(user)
    inbox = Categories.inbox_for(user)

    health =
      Category
      |> Ash.Query.filter(name == "Health")
      |> Ash.read_one!(actor: user)

    {:ok, user: user, inbox: inbox, health: health}
  end

  describe "scores_for_user/2" do
    test "open todos contribute priority × (1 + age_days)", %{user: user, inbox: inbox} do
      Todo
      |> Ash.Changeset.for_create(
        :create,
        %{title: "Fresh low", priority: :low, category_id: inbox.id},
        actor: user
      )
      |> Ash.create!()

      scores = Neglect.scores_for_user(user)
      assert Map.get(scores, inbox.id) >= 1.0
      assert Map.get(scores, inbox.id) < 2.0
    end

    test "high priority contributes 4× a low one of the same age", %{user: user, inbox: inbox} do
      Todo
      |> Ash.Changeset.for_create(
        :create,
        %{title: "Low", priority: :low, category_id: inbox.id},
        actor: user
      )
      |> Ash.create!()

      low_score = Map.get(Neglect.scores_for_user(user), inbox.id)

      # Add a high-priority todo
      Todo
      |> Ash.Changeset.for_create(
        :create,
        %{title: "High", priority: :high, category_id: inbox.id},
        actor: user
      )
      |> Ash.create!()

      both_score = Map.get(Neglect.scores_for_user(user), inbox.id)
      # High contributes ~4×, so adding it should ~5× the score
      assert both_score > 4 * low_score
    end

    test "done todos do not contribute", %{user: user, inbox: inbox} do
      Todo
      |> Ash.Changeset.for_create(
        :create,
        %{title: "Done", priority: :high, status: :done, category_id: inbox.id},
        actor: user
      )
      |> Ash.create!()

      assert Map.get(Neglect.scores_for_user(user), inbox.id) == 0.0
    end

    test "older todos score higher", %{user: user, inbox: inbox} do
      now = DateTime.utc_now()
      a_week_ago = DateTime.add(now, -7 * 86_400, :second)

      # Direct seed an older todo to bypass timestamps
      Ash.Seed.seed!(Todo, %{
        title: "Old",
        priority: :medium,
        status: :pending,
        category_id: inbox.id,
        user_id: user.id,
        inserted_at: a_week_ago,
        updated_at: a_week_ago
      })

      scores = Neglect.scores_for_user(user, now)
      # medium=2, age_days≈7, score ≈ 2 * (1 + 7) = 16
      assert Map.get(scores, inbox.id) > 10.0
      assert Map.get(scores, inbox.id) < 20.0
    end

    test "habits with shortfall contribute (min - count) × 10", %{user: user, health: health} do
      Habit
      |> Ash.Changeset.for_create(
        :create,
        %{title: "Exercise", category_id: health.id, min_count: 3, period: :week},
        actor: user
      )
      |> Ash.create!()

      # No completions yet → shortfall of 3, score 30
      score = Map.get(Neglect.scores_for_user(user), health.id)
      assert score == 30.0
    end

    test "in-progress ritual completions (nil completed_at) don't crash scoring",
         %{user: user, health: health} do
      habit =
        Habit
        |> Ash.Changeset.for_create(
          :create,
          %{title: "Morning ritual", category_id: health.id, min_count: 1, period: :day},
          actor: user
        )
        |> Ash.create!()

      Completion
      |> Ash.Changeset.for_create(:start, %{habit_id: habit.id}, actor: user)
      |> Ash.create!()

      # The in-progress completion has completed_at=nil; it must not count
      # toward min_count and must not crash DateTime.compare/2.
      score = Map.get(Neglect.scores_for_user(user), health.id)
      assert score == 10.0
    end

    test "scores roll up to ancestors", %{user: user, health: health} do
      # Create a sub-category under Health
      exercise =
        Category
        |> Ash.Changeset.for_create(
          :create,
          %{name: "Exercise", parent_id: health.id},
          actor: user
        )
        |> Ash.create!()

      Todo
      |> Ash.Changeset.for_create(
        :create,
        %{title: "Run", priority: :high, category_id: exercise.id},
        actor: user
      )
      |> Ash.create!()

      scores = Neglect.scores_for_user(user)

      # Exercise has the todo directly (~4)
      assert Map.get(scores, exercise.id) >= 4.0

      # Health (parent) should include Exercise's score
      assert Map.get(scores, health.id) == Map.get(scores, exercise.id)
    end

    test "categories with no neglect score 0.0", %{user: user, inbox: inbox} do
      scores = Neglect.scores_for_user(user)
      assert Map.has_key?(scores, inbox.id)
      assert Map.get(scores, inbox.id) == 0.0
    end
  end
end
