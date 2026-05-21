defmodule Electricbrain.Todos.Recurrence do
  @moduledoc """
  Decides whether (and when) a recurring `Todo` should have an entry in a
  given week. The `recurrence_anchor` is the canonical first instance —
  it fixes the local time-of-day, the day-of-week (`:weekly`/`:biweekly`),
  the day-of-month (`:monthly`) and the fortnightly start phase.

  Returns `{:ok, planned_at_utc}` if the todo is due in the week starting
  `week_start` (local Monday), or `:no`. Always nil for `recurrence: :none`.

  Edge cases:

    * Monthly with anchor day-of-month > days_in_target_month is clipped
      to the last day of that month (e.g. anchor on the 31st falls on
      Feb 28/29).
    * Biweekly cadence is anchored to the local-tz Monday of the anchor's
      week, so daylight-savings shifts don't flip the parity.
  """

  @type recurring_todo :: %{
          recurrence: atom(),
          recurrence_anchor: DateTime.t() | nil
        }

  @spec due_in_week?(recurring_todo, Date.t(), String.t()) :: {:ok, DateTime.t()} | :no
  def due_in_week?(todo, week_start, timezone)

  def due_in_week?(%{recurrence: :none}, _, _), do: :no
  def due_in_week?(%{recurrence_anchor: nil}, _, _), do: :no

  def due_in_week?(%{recurrence: :weekly} = todo, week_start, tz) do
    {date, time} = anchor_local_parts(todo.recurrence_anchor, tz)
    target_date = Date.add(week_start, Date.day_of_week(date) - 1)
    {:ok, local_to_utc(target_date, time, tz)}
  end

  def due_in_week?(%{recurrence: :biweekly} = todo, week_start, tz) do
    {anchor_date, time} = anchor_local_parts(todo.recurrence_anchor, tz)
    anchor_monday = monday_of(anchor_date)

    diff_days = Date.diff(week_start, anchor_monday)

    if rem(diff_days, 14) == 0 do
      target_date = Date.add(week_start, Date.day_of_week(anchor_date) - 1)
      {:ok, local_to_utc(target_date, time, tz)}
    else
      :no
    end
  end

  def due_in_week?(%{recurrence: :monthly} = todo, week_start, tz) do
    {anchor_date, time} = anchor_local_parts(todo.recurrence_anchor, tz)
    week_end = Date.add(week_start, 6)

    # The anchor's day-of-month, falling somewhere in the visible week's
    # month(s). We try this week's start-month and end-month (handles
    # weeks that span two months).
    candidate_dates =
      [week_start.month, week_end.month]
      |> Enum.uniq()
      |> Enum.map(fn month ->
        year =
          cond do
            month == week_start.month -> week_start.year
            true -> week_end.year
          end

        last_day = :calendar.last_day_of_the_month(year, month)
        day = min(anchor_date.day, last_day)
        Date.new!(year, month, day)
      end)

    case Enum.find(candidate_dates, fn d ->
           Date.compare(d, week_start) != :lt and Date.compare(d, week_end) != :gt
         end) do
      nil -> :no
      target_date -> {:ok, local_to_utc(target_date, time, tz)}
    end
  end

  defp anchor_local_parts(%DateTime{} = anchor_utc, tz) do
    local = DateTime.shift_zone!(anchor_utc, tz)
    {DateTime.to_date(local), DateTime.to_time(local)}
  end

  defp monday_of(date) do
    Date.add(date, -(Date.day_of_week(date) - 1))
  end

  defp local_to_utc(date, time, tz) do
    case DateTime.new(date, time, tz) do
      {:ok, dt} -> DateTime.shift_zone!(dt, "Etc/UTC")
      {:ambiguous, _, later} -> DateTime.shift_zone!(later, "Etc/UTC")
      {:gap, _, after_gap} -> DateTime.shift_zone!(after_gap, "Etc/UTC")
    end
  end
end
