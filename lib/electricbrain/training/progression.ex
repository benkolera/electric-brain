defmodule Electricbrain.Training.Progression do
  @moduledoc """
  Pure linear-progression maths. No Ash, no DB — inputs are plain
  maps of exercise params (`progression`, `increment_kg`, `start_reps`,
  `rep_ceiling`, `deload_pct`, `stall_threshold`), progression state
  (`current_weight_kg`, `current_reps`, `consecutive_stalls`), and a
  workout's set results (`target_reps`, `actual_reps`).

  Weight mode (barbell): every set at target = success → add the
  increment, stalls reset. Any short or skipped set = failure →
  stall count up; at the threshold, deload by `deload_pct`% rounded
  to the nearest 2.5 kg (ties round down) and reset the count.

  Reps mode (accessories): success adds a rep; past the ceiling with
  an increment set (kettlebells — next bell size) the weight bumps
  and reps reset to `start_reps`; with no increment (bodyweight) reps
  clamp at the ceiling, or grow unbounded when there's no ceiling.
  Failure leaves state unchanged — no accessory stalls in v1.

  Abandoned workouts must never be fed to `apply_result/3`.
  """

  @doc """
  Next prescription for a template slot: `%{sets, reps, weight_kg}`.
  Fixed slots carry their own reps; accessory (reps-mode) targets come
  from the state.
  """
  def prescription(params, state, slot) do
    %{
      sets: slot.sets,
      reps: slot[:reps] || state.current_reps,
      weight_kg: prescribed_weight(params, state)
    }
  end

  defp prescribed_weight(%{progression: :weight}, state), do: state.current_weight_kg
  defp prescribed_weight(%{progression: :reps}, state), do: state.current_weight_kg

  @doc """
  Applies a completed workout's set results for one exercise to its
  state, returning the new state map.
  """
  def apply_result(%{progression: :weight} = params, state, set_results) do
    if success?(set_results) do
      %{
        state
        | current_weight_kg: Decimal.add(state.current_weight_kg, params.increment_kg),
          consecutive_stalls: 0
      }
    else
      stalls = state.consecutive_stalls + 1

      if stalls >= params.stall_threshold do
        %{
          state
          | current_weight_kg: deload(state.current_weight_kg, params.deload_pct),
            consecutive_stalls: 0
        }
      else
        %{state | consecutive_stalls: stalls}
      end
    end
  end

  def apply_result(%{progression: :reps} = params, state, set_results) do
    if success?(set_results) do
      reps = state.current_reps + 1

      cond do
        is_nil(params.rep_ceiling) or reps <= params.rep_ceiling ->
          %{state | current_reps: reps, consecutive_stalls: 0}

        # Past the ceiling: kettlebells step to the next bell and reset
        # reps; pure bodyweight clamps at the ceiling.
        not is_nil(params.increment_kg) ->
          %{
            state
            | current_weight_kg:
                Decimal.add(state.current_weight_kg || Decimal.new(0), params.increment_kg),
              current_reps: params.start_reps,
              consecutive_stalls: 0
          }

        true ->
          %{state | current_reps: params.rep_ceiling, consecutive_stalls: 0}
      end
    else
      state
    end
  end

  @doc "Success ⇔ every set hit its target; a nil actual (skipped set) fails."
  def success?(set_results) do
    set_results != [] and
      Enum.all?(set_results, fn set ->
        is_integer(set.actual_reps) and set.actual_reps >= set.target_reps
      end)
  end

  @doc "Deload: weight × (1 − pct/100), rounded to the nearest 2.5 (ties down)."
  def deload(weight_kg, deload_pct) do
    factor = Decimal.sub(1, Decimal.div(deload_pct, 100))

    weight_kg
    |> Decimal.mult(factor)
    |> round_to_2p5()
  end

  @doc "Nearest 2.5 kg, ties rounding down (91.25 → 90)."
  def round_to_2p5(weight_kg) do
    quarters = Decimal.div(weight_kg, Decimal.new("2.5"))
    floor = Decimal.round(quarters, 0, :floor)
    remainder = Decimal.sub(quarters, floor)

    steps =
      if Decimal.compare(remainder, Decimal.new("0.5")) == :gt do
        Decimal.add(floor, 1)
      else
        floor
      end

    Decimal.mult(steps, Decimal.new("2.5")) |> Decimal.normalize()
  end

  @doc """
  Epley estimated 1RM: weight × (1 + reps/30), 2dp. A single at a
  weight IS the estimate — the formula's 1.033× at one rep would
  overstate it.
  """
  def epley_e1rm(weight_kg, 1), do: Decimal.round(weight_kg, 2)

  def epley_e1rm(weight_kg, reps) do
    weight_kg
    |> Decimal.mult(Decimal.add(1, Decimal.div(reps, 30)))
    |> Decimal.round(2)
  end
end
