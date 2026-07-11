defmodule Electricbrain.Meals.Generator do
  @moduledoc """
  Pure, deterministic weekly plan generation — the cookbook model:
  2 breakfasts, 2 mains alternating across lunch/dinner, 1 daily
  snack, and protein shakes topping up each day's protein gap.

  Determinism: selection rotates by ISO week number (no randomness),
  so the same library + week always produces the same plan, and
  successive weeks rotate through the library. Recipes picked last
  week are excluded when the pool allows.

  Servings are scaled per slot from fixed calorie-budget fractions
  (breakfast 28%, lunch 32%, dinner 32%, snack 8% of the target minus
  one reserved shake), rounded to practical quarter servings and
  clamped to 0.5–3.0. Shortfalls surface as human-readable warnings
  rather than failures.
  """

  @slot_budgets %{breakfast: 0.28, lunch: 0.32, dinner: 0.32, snack: 0.08}
  @min_servings 0.5
  @max_servings 3.0
  @kcal_tolerance 0.10
  @protein_tolerance 0.95

  @type recipe_in :: %{
          id: term(),
          name: String.t(),
          slot_type: atom(),
          per_serving: Electricbrain.Meals.Macros.t()
        }

  @type planned :: %{date: Date.t(), slot: atom(), recipe_id: term(), servings: float()}

  @spec generate(%{
          recipes: [recipe_in()],
          last_week_recipe_ids: MapSet.t(),
          targets: %{kcal: integer(), protein_g: integer(), fat_g: integer(), carbs_g: integer()},
          week_start: Date.t(),
          max_shakes_per_day: non_neg_integer()
        }) :: %{planned: [planned()], warnings: [String.t()]}
  def generate(%{
        recipes: recipes,
        last_week_recipe_ids: last_week_ids,
        targets: targets,
        week_start: week_start,
        max_shakes_per_day: max_shakes
      }) do
    {breakfasts, w1} = pick(recipes, last_week_ids, week_start, :breakfast, 2)
    {mains, w2} = pick(recipes, last_week_ids, week_start, :main, 2)
    {snacks, w3} = pick(recipes, last_week_ids, week_start, :snack, 1)
    {shakes, w4} = pick(recipes, last_week_ids, week_start, :shake, 1)

    snack = List.first(snacks)
    shake = List.first(shakes)
    shake = if max_shakes > 0, do: shake, else: nil

    days = Enum.map(0..4, &Date.add(week_start, &1))

    planned =
      days
      |> Enum.with_index()
      |> Enum.flat_map(fn {date, index} ->
        day_meals(date, index, breakfasts, mains, snack, targets, shake)
      end)

    {planned, shortfalls} = top_up_and_flag(planned, days, targets, shake, max_shakes)

    %{planned: planned, warnings: Enum.uniq(w1 ++ w2 ++ w3 ++ w4 ++ shortfalls)}
  end

  # --- selection ------------------------------------------------------

  defp pick(recipes, last_week_ids, week_start, slot_type, n) do
    pool =
      recipes
      |> Enum.filter(&(&1.slot_type == slot_type))
      |> Enum.sort_by(& &1.name)

    fresh = Enum.reject(pool, &MapSet.member?(last_week_ids, &1.id))
    stale = pool -- fresh

    # Fresh recipes always come first — rotation happens within the
    # fresh pool, and last week's picks only backfill a thin library.
    selected =
      if length(fresh) >= n do
        take_rotated(fresh, iso_week(week_start) * n, n)
      else
        fresh ++ take_rotated(stale, iso_week(week_start) * n, n - length(fresh))
      end

    {selected, pool_warnings(slot_type, length(pool), n)}
  end

  defp take_rotated([], _offset, _n), do: []

  defp take_rotated(list, offset, n) do
    list
    |> Stream.cycle()
    |> Stream.drop(rem(offset, length(list)))
    |> Enum.take(min(n, length(list)))
  end

  defp iso_week(date) do
    {_year, week} = :calendar.iso_week_number(Date.to_erl(date))
    week
  end

  defp pool_warnings(slot_type, 0, _n),
    do: ["No #{slot_label(slot_type)} recipes — #{empty_consequence(slot_type)}"]

  defp pool_warnings(slot_type, size, n) when size < n,
    do: ["Only #{size} #{slot_label(slot_type)} recipe — no variety this week"]

  defp pool_warnings(_slot_type, _size, _n), do: []

  defp slot_label(:breakfast), do: "breakfast"
  defp slot_label(:main), do: "main"
  defp slot_label(:snack), do: "snack"
  defp slot_label(:shake), do: "shake"

  defp empty_consequence(:breakfast), do: "breakfast slots skipped"
  defp empty_consequence(:main), do: "lunch and dinner slots skipped"
  defp empty_consequence(:snack), do: "snack slot skipped"
  defp empty_consequence(:shake), do: "protein top-up unavailable"

  # --- assignment + scaling -------------------------------------------

  defp day_meals(date, index, breakfasts, mains, snack, targets, shake) do
    shake_reserve = if shake, do: shake.per_serving.kcal, else: 0.0
    budget_kcal = max(targets.kcal - shake_reserve, 0.0)

    breakfast = alternate(breakfasts, index)
    {lunch, dinner} = lunch_dinner(mains, index)

    [
      {:breakfast, breakfast},
      {:lunch, lunch},
      {:dinner, dinner},
      {:snack, snack}
    ]
    |> Enum.flat_map(fn
      {_slot, nil} ->
        []

      {slot, recipe} ->
        budget = @slot_budgets[slot] * budget_kcal

        [
          %{
            date: date,
            slot: slot,
            recipe_id: recipe.id,
            servings: scale_servings(recipe, budget),
            per_serving: recipe.per_serving
          }
        ]
    end)
  end

  # Mon/Wed/Fri get the first pick, Tue/Thu the second (falling back to
  # the first when the library only has one).
  defp alternate([], _index), do: nil
  defp alternate([only], _index), do: only
  defp alternate([first, second | _], index), do: if(rem(index, 2) == 0, do: first, else: second)

  defp lunch_dinner([], _index), do: {nil, nil}
  defp lunch_dinner([only], _index), do: {only, only}

  defp lunch_dinner([first, second | _], index) do
    if rem(index, 2) == 0, do: {first, second}, else: {second, first}
  end

  defp scale_servings(recipe, budget_kcal) do
    case recipe.per_serving.kcal do
      kcal when kcal <= 0.0 -> 1.0
      kcal -> clamp(round_quarter(budget_kcal / kcal), @min_servings, @max_servings)
    end
  end

  # --- shake top-up + flagging ----------------------------------------

  defp top_up_and_flag(planned, days, targets, shake, max_shakes) do
    by_date = Enum.group_by(planned, & &1.date)

    {rows, warnings} =
      Enum.reduce(days, {[], []}, fn date, {rows, warnings} ->
        meals = Map.get(by_date, date, [])
        day_protein = total(meals, :protein_g)
        day_kcal = total(meals, :kcal)

        shake_row = shake_row(date, targets.protein_g - day_protein, shake, max_shakes)

        final_protein = day_protein + row_amount(shake_row, :protein_g)
        final_kcal = day_kcal + row_amount(shake_row, :kcal)

        day_warnings =
          if meals == [] and is_nil(shake_row) do
            # Nothing planned at all (empty library) — the per-slot pool
            # warnings already cover it; per-day shortfalls would be noise.
            []
          else
            day_warnings(date, final_kcal, final_protein, targets)
          end

        {rows ++ meals ++ List.wrap(shake_row), warnings ++ day_warnings}
      end)

    {Enum.map(rows, &Map.drop(&1, [:per_serving])), warnings}
  end

  defp shake_row(_date, _gap, nil, _max), do: nil
  defp shake_row(_date, gap, _shake, _max) when gap <= 0, do: nil

  defp shake_row(date, gap, shake, max_shakes) do
    case shake.per_serving.protein_g do
      protein when protein <= 0.0 ->
        nil

      protein ->
        servings = clamp(ceil_quarter(gap / protein), 0.0, max_shakes * 1.0)

        if servings > 0.0 do
          %{
            date: date,
            slot: :shake,
            recipe_id: shake.id,
            servings: servings,
            per_serving: shake.per_serving
          }
        end
    end
  end

  defp total(meals, key) do
    Enum.reduce(meals, 0.0, fn meal, acc -> acc + meal.servings * meal.per_serving[key] end)
  end

  defp row_amount(nil, _key), do: 0.0
  defp row_amount(row, key), do: row.servings * row.per_serving[key]

  defp day_warnings(date, kcal, protein, targets) do
    day = Calendar.strftime(date, "%a")

    kcal_warning =
      if targets.kcal > 0 and abs(kcal - targets.kcal) > targets.kcal * @kcal_tolerance do
        ["#{day}: #{round(kcal)} kcal vs target #{targets.kcal} (±10%)"]
      else
        []
      end

    protein_warning =
      if protein < targets.protein_g * @protein_tolerance do
        [
          "#{day}: protein #{round(protein)}g short of target #{targets.protein_g}g even with shakes"
        ]
      else
        []
      end

    kcal_warning ++ protein_warning
  end

  # --- number helpers --------------------------------------------------

  defp round_quarter(x), do: Float.round(x * 4) / 4
  defp ceil_quarter(x), do: Float.ceil(x * 4) / 4
  defp clamp(x, low, high), do: x |> max(low) |> min(high)
end
