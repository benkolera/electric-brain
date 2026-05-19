defmodule Electricbrain.SchedulableTest do
  use ExUnit.Case, async: true

  alias Electricbrain.Schedulable

  describe "effective_block/2" do
    test "expands the planned time by duration and buffers" do
      planned = ~U[2026-05-20 18:00:00Z]

      schedulable = %{
        duration_minutes: 60,
        buffer_before_minutes: 15,
        buffer_after_minutes: 10
      }

      assert {block_start, block_end} = Schedulable.effective_block(schedulable, planned)
      assert DateTime.compare(block_start, ~U[2026-05-20 17:45:00Z]) == :eq
      assert DateTime.compare(block_end, ~U[2026-05-20 19:10:00Z]) == :eq
    end

    test "treats nil duration as 0" do
      planned = ~U[2026-05-20 18:00:00Z]

      schedulable = %{
        duration_minutes: nil,
        buffer_before_minutes: 0,
        buffer_after_minutes: 0
      }

      assert {planned, planned} == Schedulable.effective_block(schedulable, planned)
    end
  end

  describe "fits_in_availability?/2" do
    test "empty availability list means anytime" do
      planned = ~U[2026-05-20 18:00:00Z]
      assert Schedulable.fits_in_availability?(planned, [])
    end

    test "fits when day_of_week and time match a window" do
      # 2026-05-20 is a Wednesday → day_of_week 3
      planned = ~U[2026-05-20 18:30:00Z]

      windows = [
        %{day_of_week: 3, start_time: ~T[18:00:00], end_time: ~T[19:00:00]}
      ]

      assert Schedulable.fits_in_availability?(planned, windows)
    end

    test "rejects when on wrong day" do
      planned = ~U[2026-05-20 18:30:00Z]

      windows = [
        %{day_of_week: 1, start_time: ~T[18:00:00], end_time: ~T[19:00:00]}
      ]

      refute Schedulable.fits_in_availability?(planned, windows)
    end

    test "rejects when outside time window" do
      planned = ~U[2026-05-20 19:30:00Z]

      windows = [
        %{day_of_week: 3, start_time: ~T[18:00:00], end_time: ~T[19:00:00]}
      ]

      refute Schedulable.fits_in_availability?(planned, windows)
    end

    test "end_time is exclusive" do
      planned = ~U[2026-05-20 19:00:00Z]

      windows = [
        %{day_of_week: 3, start_time: ~T[18:00:00], end_time: ~T[19:00:00]}
      ]

      refute Schedulable.fits_in_availability?(planned, windows)
    end
  end
end
