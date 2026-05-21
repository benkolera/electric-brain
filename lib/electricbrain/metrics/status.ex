defmodule Electricbrain.Metrics.Status do
  @moduledoc """
  "Yellow brick road" status for a metric: compare the current-period value to
  the configured goal and return `:on_track`, `:off_track`, or `:no_goal`.

  Current value depends on aggregation:
    * `:point` — the most recent measurement's value (period-independent).
    * `:sum`   — sum of measurements whose `recorded_at` falls in the current
                 user-local period bucket (day/week/month per `metric.period`).
  """

  alias Electricbrain.Timezones

  @type status :: :on_track | :off_track | :no_goal

  @doc """
  Returns the value to compare against the goal. `nil` when there's no data
  (an empty `:point` metric).
  """
  @spec current_value(map(), [map()], String.t()) :: Decimal.t() | nil
  def current_value(metric, measurements, tz \\ "Etc/UTC")

  def current_value(%{aggregation: :point}, measurements, _tz) do
    case Enum.max_by(measurements, & &1.recorded_at, DateTime, fn -> nil end) do
      nil -> nil
      m -> m.value
    end
  end

  def current_value(%{aggregation: :sum, period: period}, measurements, tz)
      when not is_nil(period) do
    start = Timezones.period_start(period, tz || "Etc/UTC")

    measurements
    |> Enum.filter(&(DateTime.compare(&1.recorded_at, start) != :lt))
    |> Enum.reduce(Decimal.new(0), fn m, acc -> Decimal.add(acc, m.value) end)
  end

  def current_value(_, _, _), do: nil

  @doc """
  `:no_goal` if the metric has no goal. Otherwise `:on_track` / `:off_track`
  by comparing the current-period value to `goal_value`. Missing data for a
  `:point` metric is treated as off-track.
  """
  @spec status(map(), [map()], String.t()) :: status
  def status(metric, measurements, tz \\ "Etc/UTC")

  def status(%{goal_kind: nil}, _, _), do: :no_goal
  def status(%{goal_value: nil}, _, _), do: :no_goal

  def status(metric, measurements, tz) do
    case current_value(metric, measurements, tz) do
      nil ->
        :off_track

      value ->
        if meets?(metric.goal_kind, value, metric.goal_value) do
          :on_track
        else
          :off_track
        end
    end
  end

  defp meets?(:at_least, value, goal), do: Decimal.compare(value, goal) != :lt
  defp meets?(:at_most, value, goal), do: Decimal.compare(value, goal) != :gt
end
