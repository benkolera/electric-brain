defmodule Electricbrain.Metrics.Chart do
  @moduledoc """
  Server-side bucketing for chart rendering. `:point` metrics return their
  raw measurements; `:sum` metrics are bucketed into the user's local
  day/week/month bins (per `metric.period`) so the client renders one point
  per bin.
  """

  @doc """
  Returns `[%{t: DateTime, v: Decimal}]` ordered ascending by `t`.

  For `:point` metrics, this is one entry per measurement. For `:sum`
  metrics, one entry per period bucket containing the bucket-start instant
  (in UTC) and the bucket total.
  """
  @spec points(map(), [map()], String.t()) :: [%{t: DateTime.t(), v: Decimal.t()}]
  def points(metric, measurements, tz \\ "Etc/UTC")

  def points(%{aggregation: :point}, measurements, _tz) do
    measurements
    |> Enum.sort_by(& &1.recorded_at, DateTime)
    |> Enum.map(&%{t: &1.recorded_at, v: &1.value})
  end

  def points(%{aggregation: :sum, period: period}, measurements, tz)
      when not is_nil(period) do
    measurements
    |> Enum.group_by(&bucket_key(&1.recorded_at, period, tz || "Etc/UTC"))
    |> Enum.map(fn {bucket_start, ms} ->
      total = Enum.reduce(ms, Decimal.new(0), &Decimal.add(&2, &1.value))
      %{t: bucket_start, v: total}
    end)
    |> Enum.sort_by(& &1.t, DateTime)
  end

  # :sum metric without a period — shouldn't happen given the resource
  # validation, but degrade gracefully.
  def points(%{aggregation: :sum}, measurements, _tz) do
    Enum.map(measurements, &%{t: &1.recorded_at, v: &1.value})
  end

  defp bucket_key(utc_datetime, period, tz) do
    utc_datetime
    |> DateTime.shift_zone!(tz)
    |> local_bucket_start(period)
    |> DateTime.shift_zone!("Etc/UTC")
  end

  defp local_bucket_start(local, :day) do
    DateTime.new!(DateTime.to_date(local), ~T[00:00:00], local.time_zone)
  end

  defp local_bucket_start(local, :week) do
    date = DateTime.to_date(local)
    days_back = Date.day_of_week(date) - 1
    monday = Date.add(date, -days_back)
    DateTime.new!(monday, ~T[00:00:00], local.time_zone)
  end

  defp local_bucket_start(local, :month) do
    date = DateTime.to_date(local)
    first_of_month = Date.new!(date.year, date.month, 1)
    DateTime.new!(first_of_month, ~T[00:00:00], local.time_zone)
  end
end
