defmodule Electricbrain.Meals.GeneratorTest do
  use ExUnit.Case, async: true

  alias Electricbrain.Meals.Generator

  # 2026-07-13 is a Monday (ISO week 29).
  @week_start ~D[2026-07-13]
  @targets %{kcal: 2400, protein_g: 180, fat_g: 67, carbs_g: 270}

  defp recipe(id, name, slot, kcal, protein, fat \\ 10.0, carbs \\ 20.0) do
    %{
      id: id,
      name: name,
      slot_type: slot,
      per_serving: %{
        kcal: kcal * 1.0,
        protein_g: protein * 1.0,
        fat_g: fat * 1.0,
        carbs_g: carbs * 1.0,
        fibre_g: 0.0
      }
    }
  end

  defp library do
    [
      recipe("b1", "Oats bowl", :breakfast, 450.0, 30.0),
      recipe("b2", "Egg wraps", :breakfast, 500.0, 35.0),
      recipe("b3", "Yogurt parfait", :breakfast, 400.0, 28.0),
      recipe("m1", "Chicken rice", :main, 600.0, 45.0),
      recipe("m2", "Beef burrito bowls", :main, 650.0, 42.0),
      recipe("m3", "Salmon traybake", :main, 550.0, 40.0),
      recipe("s1", "Cottage cheese cups", :snack, 180.0, 18.0),
      recipe("k1", "Whey shake", :shake, 150.0, 30.0)
    ]
  end

  defp generate(overrides \\ %{}) do
    Generator.generate(
      Map.merge(
        %{
          recipes: library(),
          last_week_recipe_ids: MapSet.new(),
          targets: @targets,
          week_start: @week_start,
          max_shakes_per_day: 2
        },
        overrides
      )
    )
  end

  test "produces the cookbook structure: 5 days x breakfast/lunch/dinner/snack" do
    %{planned: planned} = generate()

    dates = planned |> Enum.map(& &1.date) |> Enum.uniq() |> Enum.sort()
    assert dates == Enum.map(0..4, &Date.add(@week_start, &1))

    for date <- dates do
      slots = planned |> Enum.filter(&(&1.date == date)) |> Enum.map(& &1.slot)
      assert :breakfast in slots
      assert :lunch in slots
      assert :dinner in slots
      assert :snack in slots
    end
  end

  test "uses exactly two breakfasts and two mains, alternating" do
    %{planned: planned} = generate()

    breakfast_ids =
      planned |> Enum.filter(&(&1.slot == :breakfast)) |> Enum.map(& &1.recipe_id)

    assert length(Enum.uniq(breakfast_ids)) == 2
    # Mon/Wed/Fri share one, Tue/Thu the other.
    assert [Enum.at(breakfast_ids, 0), Enum.at(breakfast_ids, 2), Enum.at(breakfast_ids, 4)]
           |> Enum.uniq()
           |> length() == 1

    lunches = planned |> Enum.filter(&(&1.slot == :lunch)) |> Enum.map(& &1.recipe_id)
    dinners = planned |> Enum.filter(&(&1.slot == :dinner)) |> Enum.map(& &1.recipe_id)

    # Lunch and dinner swap day to day: Monday's lunch is Tuesday's dinner.
    assert Enum.at(lunches, 0) == Enum.at(dinners, 1)
    assert Enum.at(dinners, 0) == Enum.at(lunches, 1)
  end

  test "is deterministic and rotates with the ISO week" do
    a = generate()
    b = generate()
    assert a == b

    next_week = generate(%{week_start: Date.add(@week_start, 7)})
    refute picks(a, :breakfast) == picks(next_week, :breakfast)
  end

  test "excludes last week's picks when the pool allows" do
    %{planned: planned} = generate(%{last_week_recipe_ids: MapSet.new(["b1", "m1"])})

    refute "b1" in picks_list(planned, :breakfast)
    refute "m1" in picks_list(planned, :lunch)
    refute "m1" in picks_list(planned, :dinner)
  end

  test "falls back to repeats when the pool is thin, with a warning" do
    thin = [
      recipe("b1", "Oats bowl", :breakfast, 450.0, 30.0),
      recipe("m1", "Chicken rice", :main, 600.0, 45.0),
      recipe("s1", "Cottage cheese cups", :snack, 180.0, 18.0),
      recipe("k1", "Whey shake", :shake, 150.0, 30.0)
    ]

    %{planned: planned, warnings: warnings} = generate(%{recipes: thin})

    assert planned |> Enum.filter(&(&1.slot == :breakfast)) |> length() == 5
    assert Enum.any?(warnings, &(&1 =~ "Only 1 breakfast recipe"))
    assert Enum.any?(warnings, &(&1 =~ "Only 1 main recipe"))
  end

  test "empty slots are skipped with a warning" do
    %{planned: planned, warnings: warnings} =
      generate(%{recipes: Enum.reject(library(), &(&1.slot_type == :snack))})

    assert planned |> Enum.filter(&(&1.slot == :snack)) |> Enum.empty?()
    assert Enum.any?(warnings, &(&1 =~ "No snack recipes"))
  end

  test "servings are quarter-rounded within 0.5..3.0 and hit the slot budgets" do
    %{planned: planned} = generate()

    for meal <- planned do
      assert meal.servings >= 0.5
      assert meal.servings <= 3.0
      assert_in_delta meal.servings * 4, Float.round(meal.servings * 4), 1.0e-9
    end

    # Concrete numbers: budget kcal = 2400 - 150 (shake reserve) = 2250.
    # Breakfast budget 0.28 * 2250 = 630. Rotation for week 29 picks
    # b1 "Oats bowl" (450 kcal) for Mon: 630/450 = 1.4 -> 1.5 servings.
    monday_breakfast =
      Enum.find(planned, &(&1.date == @week_start and &1.slot == :breakfast))

    budget = 0.28 * (2400 - 150)
    expected = Float.round(budget / kcal_of(monday_breakfast.recipe_id) * 4) / 4
    assert monday_breakfast.servings == expected
  end

  test "adds shakes to close the protein gap, capped at max_shakes_per_day" do
    %{planned: planned} = generate()

    shakes = Enum.filter(planned, &(&1.slot == :shake))
    assert shakes != []
    assert Enum.all?(shakes, &(&1.recipe_id == "k1"))
    assert Enum.all?(shakes, &(&1.servings <= 2.0))

    # Each day's protein (incl. shake) should now be >= 95% of target
    # for this library; verify one concrete day.
    by_day = Enum.group_by(planned, & &1.date)

    for {_date, meals} <- by_day do
      protein =
        Enum.reduce(meals, 0.0, fn m, acc -> acc + m.servings * protein_of(m.recipe_id) end)

      assert protein >= @targets.protein_g * 0.95
    end
  end

  test "no shakes when protein is already met" do
    high_protein =
      library()
      |> Enum.map(fn r -> put_in(r.per_serving.protein_g, 90.0) end)

    %{planned: planned} = generate(%{recipes: high_protein})

    assert planned |> Enum.filter(&(&1.slot == :shake)) |> Enum.empty?()
  end

  test "max_shakes_per_day: 0 disables shakes entirely" do
    %{planned: planned} = generate(%{max_shakes_per_day: 0})

    assert planned |> Enum.filter(&(&1.slot == :shake)) |> Enum.empty?()
  end

  test "flags unreachable protein even with shakes" do
    weak = [
      recipe("b1", "Toast", :breakfast, 450.0, 5.0),
      recipe("m1", "Plain pasta", :main, 600.0, 8.0),
      recipe("s1", "Fruit", :snack, 180.0, 1.0),
      recipe("k1", "Weak shake", :shake, 150.0, 10.0)
    ]

    %{warnings: warnings} = generate(%{recipes: weak})

    assert Enum.any?(warnings, &(&1 =~ "protein"))
  end

  test "flags days outside the ±10% calorie window" do
    tiny = [
      recipe("b1", "Tiny breakfast", :breakfast, 100.0, 30.0),
      recipe("m1", "Tiny main", :main, 120.0, 45.0),
      recipe("s1", "Tiny snack", :snack, 50.0, 18.0)
    ]

    %{warnings: warnings} = generate(%{recipes: tiny})

    assert Enum.any?(warnings, &(&1 =~ "kcal vs target"))
  end

  test "an empty library yields no meals and warnings for every slot" do
    %{planned: planned, warnings: warnings} = generate(%{recipes: []})

    assert planned == []
    assert length(warnings) == 4
  end

  defp picks(%{planned: planned}, slot), do: picks_list(planned, slot)

  defp picks_list(planned, slot) do
    planned |> Enum.filter(&(&1.slot == slot)) |> Enum.map(& &1.recipe_id) |> Enum.uniq()
  end

  defp kcal_of(id), do: Enum.find(library(), &(&1.id == id)).per_serving.kcal
  defp protein_of(id), do: Enum.find(library(), &(&1.id == id)).per_serving.protein_g
end
