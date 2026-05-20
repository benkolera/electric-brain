defmodule ElectricbrainWeb.AgendaHelpersTest do
  use ExUnit.Case, async: true

  alias ElectricbrainWeb.AgendaHelpers

  describe "item_title/1" do
    test "uses the habit title when the entry is a habit" do
      item = %{entry: %{habit: %{title: "Read"}, todo: nil, time_block: nil}}
      assert AgendaHelpers.item_title(item) == "Read"
    end

    test "uses the todo title when the entry is a todo" do
      item = %{entry: %{habit: nil, todo: %{title: "Ship PR"}, time_block: nil}}
      assert AgendaHelpers.item_title(item) == "Ship PR"
    end

    test "uses the time_block title when the entry is a time block" do
      item = %{entry: %{habit: nil, todo: nil, time_block: %{title: "Work"}}}
      assert AgendaHelpers.item_title(item) == "Work"
    end

    test "falls back to \"Scheduled\" when no schedulable matches" do
      assert AgendaHelpers.item_title(%{entry: %{habit: nil, todo: nil, time_block: nil}}) ==
               "Scheduled"
    end
  end

  describe "format_hhmm/1" do
    test "zero-pads hours and minutes" do
      assert AgendaHelpers.format_hhmm(0) == "00:00"
      assert AgendaHelpers.format_hhmm(5) == "00:05"
      assert AgendaHelpers.format_hhmm(65) == "01:05"
      assert AgendaHelpers.format_hhmm(600) == "10:00"
    end
  end

  describe "format_time_range/2" do
    test "single-day range uses HH:MM–HH:MM" do
      item = %{
        entry: %{planned_at: ~U[2026-05-21 08:00:00Z]},
        end_time: ~U[2026-05-21 18:00:00Z]
      }

      assert AgendaHelpers.format_time_range(item, "Etc/UTC") == "08:00–18:00"
    end

    test "cross-day range prefixes each side with weekday" do
      item = %{
        entry: %{planned_at: ~U[2026-05-20 20:30:00Z]},
        end_time: ~U[2026-05-21 04:30:00Z]
      }

      assert AgendaHelpers.format_time_range(item, "Etc/UTC") == "Wed 20:30 – Thu 04:30"
    end
  end
end
