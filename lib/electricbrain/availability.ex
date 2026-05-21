defmodule Electricbrain.Availability do
  @moduledoc """
  Shared helpers for `Habits.Availability`, `Todos.Availability`, and
  `TimeBlocks.Availability` — all three carry the same `(day_of_week,
  start_time, end_time)` shape, so the duration / weekly-occurrence
  arithmetic lives in one place.
  """

  @type t :: %{
          :day_of_week => 1..7 | nil,
          :start_time => Time.t(),
          :end_time => Time.t(),
          optional(any) => any
        }

  @doc """
  Minutes between `start_time` and `end_time`. When `end_time <= start_time`
  the window wraps past midnight (so 22:00 → 06:00 is 480 minutes).
  """
  @spec duration_minutes(t()) :: non_neg_integer()
  def duration_minutes(%{start_time: start_time, end_time: end_time}) do
    diff = Time.diff(end_time, start_time, :second)
    div(if(diff <= 0, do: diff + 86_400, else: diff), 60)
  end

  @doc """
  How many times per week a window fires. `nil` day_of_week means "every
  day" — auto-prime expands it into 1..7.
  """
  @spec occurrences_per_week(t()) :: 1 | 7
  def occurrences_per_week(%{day_of_week: nil}), do: 7
  def occurrences_per_week(%{day_of_week: _}), do: 1
end
