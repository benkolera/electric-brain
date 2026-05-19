defmodule Electricbrain.Schedulable do
  @moduledoc """
  Shared helpers for anything that carries duration + buffers + availabilities
  (todos and habits). Single codepath for the planner's conflict detection.
  """

  @type schedulable :: %{
          :duration_minutes => non_neg_integer() | nil,
          :buffer_before_minutes => non_neg_integer() | nil,
          :buffer_after_minutes => non_neg_integer() | nil,
          optional(any) => any
        }

  @type availability :: %{
          :day_of_week => 1..7,
          :start_time => Time.t(),
          :end_time => Time.t(),
          optional(any) => any
        }

  @doc """
  Returns the `{block_start, block_end}` datetimes occupied by a schedulable
  planned at `planned_at`. Pulls in duration + buffer_before + buffer_after.
  """
  @spec effective_block(schedulable(), DateTime.t()) :: {DateTime.t(), DateTime.t()}
  def effective_block(schedulable, planned_at) do
    duration_s = (schedulable.duration_minutes || 0) * 60
    before_s = (schedulable.buffer_before_minutes || 0) * 60
    after_s = (schedulable.buffer_after_minutes || 0) * 60

    block_start = DateTime.add(planned_at, -before_s, :second)
    block_end = DateTime.add(planned_at, duration_s + after_s, :second)

    {block_start, block_end}
  end

  @doc """
  True when the planned datetime falls inside at least one of the availability
  windows for that day_of_week. Empty availabilities means anytime is fine.
  """
  @spec fits_in_availability?(DateTime.t(), [availability()]) :: boolean()
  def fits_in_availability?(_planned_at, []), do: true

  def fits_in_availability?(planned_at, availabilities) do
    dow = Date.day_of_week(DateTime.to_date(planned_at))
    time = DateTime.to_time(planned_at)

    Enum.any?(availabilities, fn a ->
      a.day_of_week == dow and
        Time.compare(time, a.start_time) != :lt and
        Time.compare(time, a.end_time) == :lt
    end)
  end
end
