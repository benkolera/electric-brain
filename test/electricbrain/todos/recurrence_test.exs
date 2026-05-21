defmodule Electricbrain.Todos.RecurrenceTest do
  use ExUnit.Case, async: true

  alias Electricbrain.Todos.Recurrence

  defp todo(recurrence, anchor) do
    %{recurrence: recurrence, recurrence_anchor: anchor}
  end

  describe ":none" do
    test "is never due" do
      assert Recurrence.due_in_week?(todo(:none, nil), ~D[2026-05-18], "Etc/UTC") == :no

      assert Recurrence.due_in_week?(
               todo(:none, ~U[2026-05-19 14:00:00Z]),
               ~D[2026-05-18],
               "Etc/UTC"
             ) == :no
    end
  end

  describe ":weekly" do
    test "fires every week on the anchor's day-of-week and time" do
      # Anchor: Tue 2026-05-19 14:00 UTC.
      anchor = ~U[2026-05-19 14:00:00Z]

      assert {:ok, ~U[2026-05-19 14:00:00Z]} =
               Recurrence.due_in_week?(
                 todo(:weekly, anchor),
                 ~D[2026-05-18],
                 "Etc/UTC"
               )

      assert {:ok, ~U[2026-05-26 14:00:00Z]} =
               Recurrence.due_in_week?(
                 todo(:weekly, anchor),
                 ~D[2026-05-25],
                 "Etc/UTC"
               )
    end
  end

  describe ":biweekly" do
    test "fires every fortnight from the anchor's week" do
      # Anchor: Wed 2026-05-20 10:00 UTC.
      anchor = ~U[2026-05-20 10:00:00Z]

      assert {:ok, ~U[2026-05-20 10:00:00Z]} =
               Recurrence.due_in_week?(
                 todo(:biweekly, anchor),
                 ~D[2026-05-18],
                 "Etc/UTC"
               )

      # +1 week → not due
      assert Recurrence.due_in_week?(
               todo(:biweekly, anchor),
               ~D[2026-05-25],
               "Etc/UTC"
             ) == :no

      # +2 weeks → due
      assert {:ok, ~U[2026-06-03 10:00:00Z]} =
               Recurrence.due_in_week?(
                 todo(:biweekly, anchor),
                 ~D[2026-06-01],
                 "Etc/UTC"
               )
    end

    test "respects local timezone for the anchor's day-of-week" do
      # Anchor in UTC 2026-05-19 22:00 = Wed 08:00 in Brisbane (UTC+10).
      anchor = ~U[2026-05-19 22:00:00Z]

      assert {:ok, planned} =
               Recurrence.due_in_week?(
                 todo(:biweekly, anchor),
                 ~D[2026-05-18],
                 "Australia/Brisbane"
               )

      local = DateTime.shift_zone!(planned, "Australia/Brisbane")
      assert DateTime.to_date(local) |> Date.day_of_week() == 3
      assert DateTime.to_time(local) == ~T[08:00:00]
    end
  end

  describe ":monthly" do
    test "fires when the anchor's day-of-month falls in the visible week" do
      # Anchor: 15th of the month at 09:00 UTC.
      anchor = ~U[2026-05-15 09:00:00Z]

      # Week of May 11 contains the 15th → due.
      assert {:ok, ~U[2026-05-15 09:00:00Z]} =
               Recurrence.due_in_week?(
                 todo(:monthly, anchor),
                 ~D[2026-05-11],
                 "Etc/UTC"
               )

      # Week of May 18 doesn't contain the 15th → not due.
      assert Recurrence.due_in_week?(
               todo(:monthly, anchor),
               ~D[2026-05-18],
               "Etc/UTC"
             ) == :no

      # Week of June 15 contains the 15th → due, new month.
      assert {:ok, ~U[2026-06-15 09:00:00Z]} =
               Recurrence.due_in_week?(
                 todo(:monthly, anchor),
                 ~D[2026-06-15],
                 "Etc/UTC"
               )
    end

    test "clips a day-31 anchor to the last day of shorter months" do
      anchor = ~U[2026-01-31 09:00:00Z]

      # Feb has 28 days in 2026 (non-leap). Week containing Feb 28.
      assert {:ok, ~U[2026-02-28 09:00:00Z]} =
               Recurrence.due_in_week?(
                 todo(:monthly, anchor),
                 ~D[2026-02-23],
                 "Etc/UTC"
               )
    end
  end
end
