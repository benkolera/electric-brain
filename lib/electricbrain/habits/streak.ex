defmodule Electricbrain.Habits.Streak do
  @moduledoc """
  Atomic Habits chapter 16 — "Don't break the chain." Computes per-day
  completion buckets for a habit's heatmap and a "miss twice" risk flag
  to surface in the UI before the habit drops to zero.

  All computation is per-user-timezone day boundaries, so a completion
  at 23:30 local lands on the right day even though it's stored in UTC.
  """

  alias Electricbrain.Habits.Habit

  @doc """
  Returns a list of `%{date, count, status}` for the last `lookback_days`
  (default 56 — eight weeks). Newest day last. `status` is one of:

    * `:hit`       — `count >= min_count` for daily habits, or the
                      enclosing period met its `min_count`
    * `:partial`   — `count > 0` but the enclosing period hasn't met
                      `min_count` yet (or won't, for past periods)
    * `:miss`      — `count == 0` and the day's enclosing period has
                      ended without meeting `min_count`
    * `:in_progress` — count == 0 but the enclosing period hasn't
                       ended yet; nothing to flag
    * `:future`    — the date is in the future
    * `:no_period` — habit has no `period` configured (returned only when
                     called on a fixed-schedule habit; callers usually
                     skip the heatmap for those)
  """
  def for_habit(habit, opts \\ [])

  def for_habit(%Habit{period: nil}, _opts), do: []

  def for_habit(%Habit{} = habit, opts) do
    timezone = Keyword.get(opts, :timezone, "Etc/UTC")
    lookback = Keyword.get(opts, :lookback_days, 56)
    now = Keyword.get(opts, :now, DateTime.utc_now())

    today = now |> DateTime.shift_zone!(timezone) |> DateTime.to_date()
    start_date = Date.add(today, -(lookback - 1))

    completions_by_day = bucket_completions_by_local_day(habit.completions, timezone)
    period_totals = period_totals(habit, completions_by_day, today)

    for day_offset <- 0..(lookback - 1) do
      date = Date.add(start_date, day_offset)
      count = Map.get(completions_by_day, date, 0)
      status = day_status(date, count, today, habit, period_totals)

      %{date: date, count: count, status: status}
    end
  end

  @doc """
  True when the most-recently-completed period was a miss — i.e. one
  more miss would be the second in a row. Drives the "about to miss
  twice" amber badge.

  The current period is excluded (it's still in progress and could
  still be hit). For daily habits this means yesterday's count;
  for weekly habits the previous full week, etc.
  """
  def at_risk?(habit, opts \\ [])

  def at_risk?(%Habit{period: nil}, _opts), do: false

  def at_risk?(%Habit{} = habit, opts) do
    timezone = Keyword.get(opts, :timezone, "Etc/UTC")
    now = Keyword.get(opts, :now, DateTime.utc_now())

    today = now |> DateTime.shift_zone!(timezone) |> DateTime.to_date()
    previous_period_anchor = previous_period_anchor(habit.period, today)

    completions_by_day = bucket_completions_by_local_day(habit.completions, timezone)
    count = period_count(habit.period, previous_period_anchor, completions_by_day)

    count < (habit.min_count || 1)
  end

  # ── internals ──

  defp bucket_completions_by_local_day(completions, timezone) when is_list(completions) do
    # `completed_at` is nil for in-progress ritual completions (steps
    # checked but not all yet). Skip them — they shouldn't count toward
    # the streak until they finalize, and shift_zone!(nil, _) crashes.
    Enum.reduce(completions, %{}, fn completion, acc ->
      if completion.completed_at do
        date =
          completion.completed_at
          |> DateTime.shift_zone!(timezone)
          |> DateTime.to_date()

        Map.update(acc, date, 1, &(&1 + 1))
      else
        acc
      end
    end)
  end

  defp bucket_completions_by_local_day(_, _), do: %{}

  # Pre-compute the count for each enclosing period of every day in the
  # lookback window so heatmap status lookups are O(1).
  defp period_totals(%Habit{period: period}, completions_by_day, _today) do
    completions_by_day
    |> Enum.group_by(fn {date, _} -> period_anchor(period, date) end)
    |> Enum.into(%{}, fn {anchor, days} ->
      total = Enum.sum(Enum.map(days, fn {_d, c} -> c end))
      {anchor, total}
    end)
  end

  defp day_status(date, count, today, habit, period_totals) do
    cond do
      Date.compare(date, today) == :gt ->
        :future

      true ->
        anchor = period_anchor(habit.period, date)
        period_end_date = period_end_date(habit.period, anchor)
        period_total = Map.get(period_totals, anchor, 0)
        min_count = habit.min_count || 1
        period_complete? = Date.compare(period_end_date, today) != :gt

        cond do
          period_total >= min_count and count > 0 -> :hit
          period_total >= min_count -> :hit
          count > 0 -> :partial
          period_complete? -> :miss
          true -> :in_progress
        end
    end
  end

  defp period_anchor(:day, date), do: date

  defp period_anchor(:week, date) do
    days_back = Date.day_of_week(date) - 1
    Date.add(date, -days_back)
  end

  defp period_anchor(:month, date), do: Date.new!(date.year, date.month, 1)

  defp period_end_date(:day, anchor), do: anchor
  defp period_end_date(:week, anchor), do: Date.add(anchor, 6)

  defp period_end_date(:month, anchor) do
    days_in_month = Date.days_in_month(anchor)
    Date.new!(anchor.year, anchor.month, days_in_month)
  end

  defp previous_period_anchor(:day, today), do: Date.add(today, -1)

  defp previous_period_anchor(:week, today) do
    current_anchor = period_anchor(:week, today)
    Date.add(current_anchor, -7)
  end

  defp previous_period_anchor(:month, today) do
    current_anchor = period_anchor(:month, today)
    last_day_prev_month = Date.add(current_anchor, -1)
    period_anchor(:month, last_day_prev_month)
  end

  defp period_count(period, anchor, completions_by_day) do
    end_date = period_end_date(period, anchor)

    Enum.reduce(Date.range(anchor, end_date), 0, fn date, acc ->
      acc + Map.get(completions_by_day, date, 0)
    end)
  end
end
