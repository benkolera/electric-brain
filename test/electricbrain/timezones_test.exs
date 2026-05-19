defmodule Electricbrain.TimezonesTest do
  use ExUnit.Case, async: true

  alias Electricbrain.Timezones

  describe "valid?/1" do
    test "accepts known IANA zones" do
      assert Timezones.valid?("Etc/UTC")
      assert Timezones.valid?("Australia/Brisbane")
      assert Timezones.valid?("America/New_York")
    end

    test "rejects unknown zones" do
      refute Timezones.valid?("Mars/Olympus_Mons")
      refute Timezones.valid?("")
      refute Timezones.valid?(nil)
    end
  end

  describe "period_start/3" do
    test ":day uses local midnight, returned in UTC" do
      # 2026-05-19 13:00 UTC is 2026-05-19 23:00 in Brisbane (UTC+10).
      # Local midnight for that day is 2026-05-19 00:00 +10 == 2026-05-18 14:00 UTC.
      now = ~U[2026-05-19 13:00:00Z]

      result = Timezones.period_start(:day, "Australia/Brisbane", now)
      assert DateTime.compare(result, ~U[2026-05-18 14:00:00Z]) == :eq
    end

    test ":day in UTC is plain UTC midnight" do
      now = ~U[2026-05-19 13:00:00Z]

      result = Timezones.period_start(:day, "Etc/UTC", now)
      assert DateTime.compare(result, ~U[2026-05-19 00:00:00Z]) == :eq
    end

    test ":week returns the Monday of the local week" do
      # 2026-05-19 is a Tuesday in Brisbane (UTC+10).
      # Local Monday 2026-05-18 00:00 +10 == 2026-05-17 14:00 UTC.
      now = ~U[2026-05-19 13:00:00Z]

      result = Timezones.period_start(:week, "Australia/Brisbane", now)
      assert DateTime.compare(result, ~U[2026-05-17 14:00:00Z]) == :eq
    end

    test ":month returns local first-of-month" do
      now = ~U[2026-05-19 13:00:00Z]

      result = Timezones.period_start(:month, "Australia/Brisbane", now)
      assert DateTime.compare(result, ~U[2026-04-30 14:00:00Z]) == :eq
    end

    test "TZ change near boundary moves the bucket" do
      # 2026-05-18 18:00 UTC: Sydney clock reads 2026-05-19 04:00 → "today" is the 19th.
      # UTC clock reads "today" is the 18th. Verify the bucket differs.
      now = ~U[2026-05-18 18:00:00Z]
      assert ~U[2026-05-18 14:00:00Z] = Timezones.period_start(:day, "Australia/Sydney", now)
      assert ~U[2026-05-18 00:00:00Z] = Timezones.period_start(:day, "Etc/UTC", now)
    end
  end
end
