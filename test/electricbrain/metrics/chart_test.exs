defmodule Electricbrain.Metrics.ChartTest do
  use ExUnit.Case, async: true

  alias Electricbrain.Metrics.Chart

  defp measurement(value, recorded_at) do
    %{value: Decimal.new(value), recorded_at: recorded_at}
  end

  describe "points/3" do
    test ":point returns raw measurements sorted ascending" do
      out =
        Chart.points(
          %{aggregation: :point, period: nil},
          [
            measurement("2", ~U[2026-05-20 09:00:00Z]),
            measurement("1", ~U[2026-05-19 09:00:00Z])
          ]
        )

      assert Enum.map(out, & &1.t) == [~U[2026-05-19 09:00:00Z], ~U[2026-05-20 09:00:00Z]]
      assert Enum.map(out, & &1.v) == [Decimal.new("1"), Decimal.new("2")]
    end

    test ":sum buckets by local day" do
      out =
        Chart.points(
          %{aggregation: :sum, period: :day},
          [
            measurement("0.5", ~U[2026-05-20 09:00:00Z]),
            measurement("1.0", ~U[2026-05-20 13:00:00Z]),
            measurement("0.7", ~U[2026-05-21 08:00:00Z])
          ],
          "Etc/UTC"
        )

      # Two daily buckets: 1.5 on May 20, 0.7 on May 21
      assert Enum.map(out, & &1.t) == [
               ~U[2026-05-20 00:00:00Z],
               ~U[2026-05-21 00:00:00Z]
             ]

      [a, b] = Enum.map(out, & &1.v)
      assert Decimal.equal?(a, Decimal.new("1.5"))
      assert Decimal.equal?(b, Decimal.new("0.7"))
    end

    test ":sum + :week buckets to ISO weeks (Monday start)" do
      # Wed and Thu of the same week (May 20 = Wed, May 21 = Thu) → one bucket
      out =
        Chart.points(
          %{aggregation: :sum, period: :week},
          [
            measurement("3", ~U[2026-05-20 09:00:00Z]),
            measurement("4", ~U[2026-05-21 09:00:00Z])
          ],
          "Etc/UTC"
        )

      assert length(out) == 1
      [bucket] = out
      # Week containing May 20/21 starts Mon May 18.
      assert bucket.t == ~U[2026-05-18 00:00:00Z]
      assert Decimal.equal?(bucket.v, Decimal.new("7"))
    end
  end
end
