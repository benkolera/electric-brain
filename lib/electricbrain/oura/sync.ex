defmodule Electricbrain.Oura.Sync do
  @moduledoc """
  Pulls Oura daily activity into two auto-created Metrics ("Oura
  active kcal" / "Oura total kcal", point-per-day) so calorie burn
  charts like any other series and feeds the adaptive TDEE.

  Idempotent per local day: a day's measurement is stored at noon in
  the user's timezone and updated in place on re-sync. Only completed
  days sync (yesterday and back — today's Oura numbers are partial).

  The metrics are found by name — renaming them in the Metrics UI
  makes the sync recreate fresh ones.
  """

  require Ash.Query
  require Logger

  alias Electricbrain.Metrics.Measurement
  alias Electricbrain.Metrics.Metric
  alias Electricbrain.Oura

  @active_metric "Oura active kcal"
  @total_metric "Oura total kcal"
  @lookback_days 14
  @min_observed_days 7

  @doc """
  Syncs the trailing #{@lookback_days} completed days for a connected
  user. Returns `{:ok, upserted_count}` or `{:error, reason}`.
  """
  def sync_user(user, opts \\ []) do
    today = user.timezone |> DateTime.now!() |> DateTime.to_date()
    start_date = Date.add(today, -@lookback_days)
    end_date = Date.add(today, -1)

    with {:ok, days} <- Oura.daily_activity(user, start_date, end_date, opts) do
      active = find_or_create_metric(user, @active_metric)
      total = find_or_create_metric(user, @total_metric)

      count =
        Enum.reduce(days, 0, fn day, acc ->
          acc +
            upsert_measurement(user, active, day.day, day.active_calories) +
            upsert_measurement(user, total, day.day, day.total_calories)
        end)

      {:ok, count}
    end
  end

  @doc """
  The observed TDEE: mean of the trailing #{@lookback_days}-day
  "#{@total_metric}" measurements, requiring at least
  #{@min_observed_days} days of data. `{:ok, kcal}` or `:none`.
  """
  def observed_tdee(user, now \\ DateTime.utc_now()) do
    with %Metric{} = metric <- find_metric(user, @total_metric) do
      since = DateTime.add(now, -@lookback_days * 86_400, :second)

      values =
        Measurement
        |> Ash.Query.filter(metric_id == ^metric.id)
        |> Ash.read!(actor: user)
        |> Enum.filter(&(DateTime.compare(&1.recorded_at, since) != :lt))
        |> Enum.map(&Decimal.to_float(&1.value))

      if length(values) >= @min_observed_days do
        {:ok, round(Enum.sum(values) / length(values))}
      else
        :none
      end
    else
      _ -> :none
    end
  end

  defp find_metric(user, name) do
    Metric
    |> Ash.Query.filter(name == ^name)
    |> Ash.read_one!(actor: user)
  end

  defp find_or_create_metric(user, name) do
    case find_metric(user, name) do
      %Metric{} = metric ->
        metric

      nil ->
        Metric
        |> Ash.Changeset.for_create(
          :create,
          %{name: name, unit: "kcal", aggregation: :point, period: :day},
          actor: user
        )
        |> Ash.create!()
    end
  end

  # One measurement per local day, stored at local noon; re-sync
  # updates the value in place. Returns 1 if a row changed, 0 if not.
  defp upsert_measurement(user, metric, day, value) do
    recorded_at =
      day
      |> DateTime.new!(~T[12:00:00], user.timezone)
      |> DateTime.shift_zone!("Etc/UTC")

    day_start = DateTime.new!(day, ~T[00:00:00], user.timezone)
    day_end = DateTime.add(day_start, 86_400, :second)

    existing =
      Measurement
      |> Ash.Query.filter(
        metric_id == ^metric.id and recorded_at >= ^day_start and recorded_at < ^day_end
      )
      |> Ash.read!(actor: user)
      |> List.first()

    value = Decimal.new(value)

    case existing do
      nil ->
        Measurement
        |> Ash.Changeset.for_create(
          :create,
          %{metric_id: metric.id, value: value, recorded_at: recorded_at},
          actor: user
        )
        |> Ash.create!()

        1

      %Measurement{value: current} ->
        if Decimal.equal?(current, value) do
          0
        else
          existing
          |> Ash.Changeset.for_update(:update, %{value: value}, actor: user)
          |> Ash.update!()

          1
        end
    end
  end
end
