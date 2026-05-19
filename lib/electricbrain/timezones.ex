defmodule Electricbrain.Timezones do
  @moduledoc """
  Small helpers around IANA time zones. Validation and TZ-aware period
  boundary calculations.
  """

  @doc """
  True iff the given string is a valid IANA timezone known to the configured
  time zone database.
  """
  @spec valid?(String.t()) :: boolean()
  def valid?(tz) when is_binary(tz) do
    case DateTime.now(tz) do
      {:ok, _} -> true
      _ -> false
    end
  end

  def valid?(_), do: false

  @doc """
  Returns the UTC `DateTime` at which the current `period` starts for the given
  user `timezone`. Used to bucket habit completions into "this day / week /
  month" from the user's local perspective.

      iex> period_start(:day, "Australia/Brisbane", ~U[2026-05-19 13:00:00Z])
      ~U[2026-05-18 14:00:00Z]
  """
  @spec period_start(:day | :week | :month, String.t(), DateTime.t()) :: DateTime.t()
  def period_start(period, timezone, now \\ DateTime.utc_now()) do
    local = DateTime.shift_zone!(now, timezone)
    local_start = local_period_start(local, period)

    local_start
    |> DateTime.shift_zone!("Etc/UTC")
  end

  defp local_period_start(local, :day) do
    DateTime.new!(DateTime.to_date(local), ~T[00:00:00], local.time_zone)
  end

  defp local_period_start(local, :week) do
    date = DateTime.to_date(local)
    days_back = Date.day_of_week(date) - 1
    monday = Date.add(date, -days_back)
    DateTime.new!(monday, ~T[00:00:00], local.time_zone)
  end

  defp local_period_start(local, :month) do
    date = DateTime.to_date(local)
    first_of_month = Date.new!(date.year, date.month, 1)
    DateTime.new!(first_of_month, ~T[00:00:00], local.time_zone)
  end
end
