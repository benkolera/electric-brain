defmodule Electricbrain.Metrics.StatusTest do
  use ExUnit.Case, async: true

  alias Electricbrain.Metrics.Status

  defp metric(attrs) do
    Map.merge(
      %{
        aggregation: :point,
        period: nil,
        goal_kind: nil,
        goal_value: nil
      },
      Map.new(attrs)
    )
  end

  defp measurement(value, recorded_at) do
    %{value: Decimal.new(value), recorded_at: recorded_at}
  end

  describe "status/3" do
    test ":no_goal when goal isn't configured" do
      assert Status.status(metric([]), []) == :no_goal

      assert Status.status(
               metric(goal_kind: nil, goal_value: Decimal.new("5")),
               []
             ) == :no_goal
    end

    test ":point metric with at_least goal: latest >= goal" do
      m =
        metric(
          aggregation: :point,
          period: :day,
          goal_kind: :at_least,
          goal_value: Decimal.new("80")
        )

      assert Status.status(m, [measurement("82", ~U[2026-05-20 09:00:00Z])]) == :on_track
      assert Status.status(m, [measurement("75", ~U[2026-05-20 09:00:00Z])]) == :off_track
    end

    test ":point metric with at_most goal: latest <= goal" do
      m =
        metric(
          aggregation: :point,
          period: :day,
          goal_kind: :at_most,
          goal_value: Decimal.new("80")
        )

      assert Status.status(m, [measurement("79", ~U[2026-05-20 09:00:00Z])]) == :on_track
      assert Status.status(m, [measurement("82", ~U[2026-05-20 09:00:00Z])]) == :off_track
    end

    test ":point with no measurements is :off_track when a goal is set" do
      m =
        metric(
          aggregation: :point,
          period: :day,
          goal_kind: :at_least,
          goal_value: Decimal.new("1")
        )

      assert Status.status(m, []) == :off_track
    end

    test ":sum metric sums only the current period" do
      m =
        metric(
          aggregation: :sum,
          period: :day,
          goal_kind: :at_least,
          goal_value: Decimal.new("2")
        )

      now = DateTime.utc_now()
      today_morning = DateTime.add(now, -1 * 60 * 60, :second)
      yesterday = DateTime.add(now, -25 * 60 * 60, :second)

      # 0.5 + 1.0 = 1.5 < 2 → off track (yesterday's 5L doesn't count)
      assert Status.status(
               m,
               [
                 measurement("0.5", today_morning),
                 measurement("1.0", today_morning),
                 measurement("5", yesterday)
               ],
               "Etc/UTC"
             ) == :off_track

      # bump today's total to 2.5 → on track
      assert Status.status(
               m,
               [
                 measurement("0.5", today_morning),
                 measurement("1.0", today_morning),
                 measurement("1.0", today_morning)
               ],
               "Etc/UTC"
             ) == :on_track
    end
  end
end
