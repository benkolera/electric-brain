defmodule Electricbrain.Meals.Weight do
  @moduledoc """
  Thin reader over the Metrics domain for the profile's weight series:
  the latest reading (feeds BMR) and the week-over-week change (the
  "is the plan working?" feedback line). Weeks are bucketed by the
  user's local Monday via `Electricbrain.Timezones.period_start/3`.
  """

  require Ash.Query

  alias Electricbrain.Metrics.Measurement
  alias Electricbrain.Timezones

  @doc """
  Latest weight measurement, or `:none` when no metric is linked or it
  has no measurements. Returns `{:ok, %{kg: Decimal, recorded_at: dt}}`.
  """
  def latest(_user, %{weight_metric_id: nil}), do: :none

  def latest(user, profile) do
    case metric_latest(user, profile.weight_metric_id) do
      :none -> :none
      {:ok, %{value: value, recorded_at: at}} -> {:ok, %{kg: value, recorded_at: at}}
    end
  end

  @doc "Latest measurement of any metric: `{:ok, %{value, recorded_at}}` or `:none`."
  def metric_latest(user, metric_id) do
    case read_latest(user, metric_id, nil, nil) do
      nil -> :none
      m -> {:ok, %{value: m.value, recorded_at: m.recorded_at}}
    end
  end

  @doc """
  Latest-this-week minus latest-last-week, or `:none` if either week
  has no reading. Returns `{:ok, Decimal}` (negative = lost weight).
  """
  def week_delta(user, profile, now \\ DateTime.utc_now())

  def week_delta(_user, %{weight_metric_id: nil}, _now), do: :none

  def week_delta(user, profile, now) do
    metric_week_delta(user, profile.weight_metric_id, now)
  end

  @doc "Week-over-week delta for any metric: `{:ok, Decimal}` or `:none`."
  def metric_week_delta(user, metric_id, now \\ DateTime.utc_now()) do
    week_start = Timezones.period_start(:week, user.timezone, now)
    prev_start = Timezones.period_start(:week, user.timezone, DateTime.add(week_start, -1))

    this_week = read_latest(user, metric_id, week_start, nil)
    last_week = read_latest(user, metric_id, prev_start, week_start)

    case {this_week, last_week} do
      {%{value: a}, %{value: b}} -> {:ok, Decimal.sub(a, b)}
      _ -> :none
    end
  end

  defp read_latest(user, metric_id, at_or_after, before) do
    Measurement
    |> Ash.Query.filter(metric_id == ^metric_id)
    |> then(fn q ->
      if at_or_after, do: Ash.Query.filter(q, recorded_at >= ^at_or_after), else: q
    end)
    |> then(fn q -> if before, do: Ash.Query.filter(q, recorded_at < ^before), else: q end)
    |> Ash.Query.sort(recorded_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one!(actor: user)
  end
end
