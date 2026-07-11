defmodule Electricbrain.Training.GeneratorTest do
  use ExUnit.Case, async: true

  alias Electricbrain.Training.Generator

  # A compact model of the seeded defaults.
  defp fixed(exercise, sets, reps),
    do: %{kind: :fixed, exercise_id: exercise, exercise_name: exercise, sets: sets, reps: reps}

  defp accessory(sets \\ 3),
    do: %{kind: :accessory, exercise_id: nil, exercise_name: nil, sets: sets, reps: nil}

  defp templates do
    [
      %{
        id: "t-a",
        name: "A",
        position: 0,
        slots: [
          fixed("squat", 5, 5),
          fixed("bench", 5, 5),
          fixed("row", 5, 5),
          accessory(),
          accessory()
        ]
      },
      %{
        id: "t-b",
        name: "B",
        position: 1,
        slots: [
          fixed("squat", 5, 5),
          fixed("ohp", 5, 5),
          fixed("deadlift", 1, 5),
          accessory(),
          accessory()
        ]
      }
    ]
  end

  defp pool do
    [
      %{id: "dips", name: "Ring dips"},
      %{id: "pullups", name: "Pull ups"},
      %{id: "swings", name: "Swings"},
      %{id: "highpull", name: "Sumo high pull"},
      %{id: "tgu", name: "TGU"}
    ]
    |> Enum.sort_by(& &1.name)
  end

  defp weight_params,
    do: %{
      progression: :weight,
      increment_kg: Decimal.new("2.5"),
      start_reps: nil,
      rep_ceiling: nil,
      deload_pct: Decimal.new(10),
      stall_threshold: 3
    }

  defp reps_params,
    do: %{
      progression: :reps,
      increment_kg: Decimal.new(4),
      start_reps: 10,
      rep_ceiling: 20,
      deload_pct: Decimal.new(10),
      stall_threshold: 3
    }

  defp params_by_id do
    barbell = ~w(squat bench row ohp deadlift)
    accessories = Enum.map(pool(), & &1.id)

    Map.new(barbell, &{&1, weight_params()})
    |> Map.merge(Map.new(accessories, &{&1, reps_params()}))
  end

  defp states_by_id do
    %{
      "squat" => state("82.5"),
      "bench" => state("60"),
      "row" => state("55"),
      "ohp" => state("40"),
      "deadlift" => state("120")
    }
    |> Map.merge(Map.new(pool(), &{&1.id, state("16", 12)}))
  end

  defp state(weight, reps \\ nil),
    do: %{
      current_weight_kg: weight && Decimal.new(weight),
      current_reps: reps,
      consecutive_stalls: 0
    }

  defp generate(overrides \\ %{}) do
    Generator.next_session(
      Map.merge(
        %{
          templates: templates(),
          last_template_position: nil,
          completed_count: 0,
          accessory_pool: pool(),
          params_by_exercise_id: params_by_id(),
          states_by_exercise_id: states_by_id()
        },
        overrides
      )
    )
  end

  test "fresh user gets template A with the classic prescription" do
    %{template: template, items: items} = generate()

    assert template.name == "A"

    assert [squat, bench, row | _accessories] = items
    assert {squat.exercise_name, squat.sets, squat.reps} == {"squat", 5, 5}
    assert Decimal.equal?(squat.weight_kg, Decimal.new("82.5"))
    assert bench.exercise_name == "bench"
    assert row.exercise_name == "row"
  end

  test "alternates A -> B -> A (wrap)" do
    assert %{template: %{name: "B"}} = generate(%{last_template_position: 0})
    assert %{template: %{name: "A"}} = generate(%{last_template_position: 1})
  end

  test "abandoning does not advance (same last position, same template)" do
    a = generate(%{last_template_position: 0, completed_count: 3})
    b = generate(%{last_template_position: 0, completed_count: 3})
    assert a == b
  end

  test "deadlift slot prescribes 1x5 at its own weight" do
    %{items: items} = generate(%{last_template_position: 0})
    deadlift = Enum.find(items, &(&1.exercise_name == "deadlift"))

    assert {deadlift.sets, deadlift.reps} == {1, 5}
    assert Decimal.equal?(deadlift.weight_kg, Decimal.new(120))
  end

  test "accessory slots take target reps from state and rotate the pool evenly" do
    # completed_count 0 -> pool[0], pool[1]; count 1 -> pool[2], pool[3];
    # count 2 -> pool[4], pool[0]  (5 accessories, 2 slots/session)
    names = fn count ->
      %{items: items} = generate(%{completed_count: count})

      items
      |> Enum.filter(&(&1.slot_kind == :accessory))
      |> Enum.map(& &1.exercise_name)
    end

    sorted_pool = Enum.map(pool(), & &1.name)

    assert names.(0) == Enum.slice(sorted_pool, 0, 2)
    assert names.(1) == Enum.slice(sorted_pool, 2, 2)
    assert names.(2) == [Enum.at(sorted_pool, 4), Enum.at(sorted_pool, 0)]

    # Reps come from the exercise state (12), sets from the slot (3).
    %{items: items} = generate()
    accessory = Enum.find(items, &(&1.slot_kind == :accessory))
    assert {accessory.sets, accessory.reps} == {3, 12}
    assert Decimal.equal?(accessory.weight_kg, Decimal.new(16))
  end

  test "empty accessory pool just skips accessory slots" do
    %{items: items} = generate(%{accessory_pool: []})

    assert Enum.count(items, &(&1.slot_kind == :accessory)) == 0
    assert Enum.count(items, &(&1.slot_kind == :fixed)) == 3
  end

  test "no templates is an error" do
    assert {:error, :no_templates} = generate(%{templates: []})
  end
end
