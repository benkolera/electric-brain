defmodule Electricbrain.Neglect do
  @moduledoc """
  Per-category neglect scoring. v1 formula:

    * open todos contribute `priority_weight * (1 + age_days)` where
      `low=1, medium=2, high=4`
    * habits whose current-period completion count is below `min_count`
      contribute `(min_count - count) * 10`

  Scores roll up the category tree — a parent's score includes all
  descendants'.
  """

  require Ash.Query

  alias Electricbrain.Categories
  alias Electricbrain.Habits.Habit
  alias Electricbrain.Timezones
  alias Electricbrain.Todos.Todo

  @priority_weight %{low: 1, medium: 2, high: 4}
  @habit_overdue_factor 10

  @doc """
  Returns a map of `category_id => score (float)` with scores rolled up the tree.
  Categories with no neglect (and no neglect from descendants) are still present
  with a 0.0 score, so all known category ids are keys.
  """
  def scores_for_user(user, now \\ DateTime.utc_now()) do
    categories = Categories.list_with_paths(user)
    by_id = Map.new(categories, &{&1.id, &1})

    todos =
      Todo
      |> Ash.Query.filter(status != :done)
      |> Ash.read!(actor: user)

    habits =
      Habit
      |> Ash.Query.load(:completions)
      |> Ash.read!(actor: user)

    leaf_scores =
      Map.new(categories, fn cat ->
        todo_score = score_todos(todos, cat.id, now)
        habit_score = score_habits(habits, cat.id, user.timezone, now)
        {cat.id, todo_score + habit_score}
      end)

    roll_up(leaf_scores, by_id)
  end

  defp score_todos(todos, category_id, now) do
    todos
    |> Enum.filter(&(&1.category_id == category_id))
    |> Enum.map(&todo_score(&1, now))
    |> Enum.sum()
  end

  defp todo_score(todo, now) do
    age_days = DateTime.diff(now, todo.inserted_at, :second) / 86_400
    weight = Map.get(@priority_weight, todo.priority, 1)
    weight * (1 + max(age_days, 0))
  end

  defp score_habits(habits, category_id, timezone, now) do
    habits
    |> Enum.filter(&(&1.category_id == category_id))
    |> Enum.map(&habit_score(&1, timezone, now))
    |> Enum.sum()
  end

  defp habit_score(habit, timezone, now) do
    start = Timezones.period_start(habit.period, timezone, now)
    count = Enum.count(habit.completions, &(DateTime.compare(&1.completed_at, start) != :lt))

    if count < habit.min_count do
      (habit.min_count - count) * @habit_overdue_factor
    else
      0
    end
  end

  defp roll_up(direct_scores, by_id) do
    Enum.reduce(direct_scores, direct_scores, fn {id, direct}, acc ->
      add_to_ancestors(acc, by_id, parent_of(id, by_id), direct)
    end)
  end

  defp add_to_ancestors(acc, _by_id, nil, _score), do: acc

  defp add_to_ancestors(acc, by_id, parent_id, score) do
    acc
    |> Map.update(parent_id, score, &(&1 + score))
    |> add_to_ancestors(by_id, parent_of(parent_id, by_id), score)
  end

  defp parent_of(id, by_id) do
    case Map.get(by_id, id) do
      nil -> nil
      cat -> cat.parent_id
    end
  end
end
