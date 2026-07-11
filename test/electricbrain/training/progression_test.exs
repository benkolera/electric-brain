defmodule Electricbrain.Training.ProgressionTest do
  use ExUnit.Case, async: true

  alias Electricbrain.Training.Progression

  defp weight_params(overrides \\ %{}) do
    Map.merge(
      %{
        progression: :weight,
        increment_kg: Decimal.new("2.5"),
        start_reps: nil,
        rep_ceiling: nil,
        deload_pct: Decimal.new(10),
        stall_threshold: 3
      },
      overrides
    )
  end

  defp reps_params(overrides \\ %{}) do
    Map.merge(
      %{
        progression: :reps,
        increment_kg: Decimal.new(4),
        start_reps: 10,
        rep_ceiling: 20,
        deload_pct: Decimal.new(10),
        stall_threshold: 3
      },
      overrides
    )
  end

  defp state(weight, reps \\ nil, stalls \\ 0) do
    %{
      current_weight_kg: weight && Decimal.new(weight),
      current_reps: reps,
      consecutive_stalls: stalls
    }
  end

  defp sets(pairs), do: Enum.map(pairs, fn {t, a} -> %{target_reps: t, actual_reps: a} end)

  defp all_hit(n, reps), do: sets(List.duplicate({reps, reps}, n))

  describe "weight mode" do
    test "success adds the increment and clears stalls" do
      new = Progression.apply_result(weight_params(), state("60", nil, 1), all_hit(5, 5))

      assert Decimal.equal?(new.current_weight_kg, Decimal.new("62.5"))
      assert new.consecutive_stalls == 0
    end

    test "deadlift 1x5 with +5 increment" do
      params = weight_params(%{increment_kg: Decimal.new(5)})
      new = Progression.apply_result(params, state("140"), all_hit(1, 5))

      assert Decimal.equal?(new.current_weight_kg, Decimal.new(145))
    end

    test "a short set is a failure: stall count rises, weight holds" do
      results = sets([{5, 5}, {5, 5}, {5, 4}, {5, 5}, {5, 5}])
      new = Progression.apply_result(weight_params(), state("100"), results)

      assert Decimal.equal?(new.current_weight_kg, Decimal.new(100))
      assert new.consecutive_stalls == 1
    end

    test "a skipped set (nil actual) is a failure" do
      results = sets([{5, 5}, {5, nil}])
      new = Progression.apply_result(weight_params(), state("100"), results)

      assert new.consecutive_stalls == 1
    end

    test "third stall deloads 10% rounded to 2.5 and resets the count" do
      missed = sets(List.duplicate({5, 4}, 5))

      new = Progression.apply_result(weight_params(), state("100", nil, 2), missed)

      assert Decimal.equal?(new.current_weight_kg, Decimal.new(90))
      assert new.consecutive_stalls == 0

      # 102.5 × 0.9 = 92.25 → nearest 2.5 is 92.5 (0.25 away vs 2.25).
      new = Progression.apply_result(weight_params(), state("102.5", nil, 2), missed)
      assert Decimal.equal?(new.current_weight_kg, Decimal.new("92.5"))
    end

    test "rounding ties go down: 91.25 -> 90" do
      assert Decimal.equal?(Progression.round_to_2p5(Decimal.new("91.25")), Decimal.new(90))
      assert Decimal.equal?(Progression.round_to_2p5(Decimal.new("91.26")), Decimal.new("92.5"))
      assert Decimal.equal?(Progression.round_to_2p5(Decimal.new(90)), Decimal.new(90))
    end
  end

  describe "reps mode" do
    test "success adds a rep below the ceiling" do
      new = Progression.apply_result(reps_params(), state("16", 10), all_hit(3, 10))

      assert new.current_reps == 11
      assert Decimal.equal?(new.current_weight_kg, Decimal.new(16))
    end

    test "past the ceiling with an increment: next bell, reps reset" do
      new = Progression.apply_result(reps_params(), state("16", 20), all_hit(3, 20))

      assert Decimal.equal?(new.current_weight_kg, Decimal.new(20))
      assert new.current_reps == 10
    end

    test "past the ceiling without an increment clamps (weighted-later bodyweight)" do
      params = reps_params(%{increment_kg: nil, rep_ceiling: 12, start_reps: 5})
      new = Progression.apply_result(params, state(nil, 12), all_hit(3, 12))

      assert new.current_reps == 12
      assert is_nil(new.current_weight_kg)
    end

    test "no ceiling: unbounded rep adding (pull ups)" do
      params = reps_params(%{increment_kg: nil, rep_ceiling: nil, start_reps: 5})
      new = Progression.apply_result(params, state(nil, 21), all_hit(3, 21))

      assert new.current_reps == 22
    end

    test "failure leaves state unchanged" do
      before = state("16", 14)
      new = Progression.apply_result(reps_params(), before, sets([{14, 14}, {14, 12}, {14, 14}]))

      assert new == before
    end
  end

  test "empty set list is a failure, not a success" do
    refute Progression.success?([])
  end

  test "epley e1rm: 100 x 5 -> 116.67" do
    assert Decimal.equal?(
             Progression.epley_e1rm(Decimal.new(100), 5),
             Decimal.new("116.67")
           )

    # A single at a weight IS the estimate.
    assert Decimal.equal?(Progression.epley_e1rm(Decimal.new(140), 1), Decimal.new(140))
  end
end
