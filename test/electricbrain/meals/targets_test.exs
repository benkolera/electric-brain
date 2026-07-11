defmodule Electricbrain.Meals.TargetsTest do
  use ExUnit.Case, async: true

  alias Electricbrain.Meals.Targets

  describe "bmr/4 — Mifflin-St Jeor known values" do
    test "male: 90kg, 180cm, 35y" do
      # 10*90 + 6.25*180 - 5*35 + 5 = 900 + 1125 - 175 + 5
      assert_in_delta Targets.bmr(:male, 90.0, 180.0, 35), 1855.0, 0.001
    end

    test "female: 65kg, 165cm, 30y" do
      # 10*65 + 6.25*165 - 5*30 - 161 = 650 + 1031.25 - 150 - 161
      assert_in_delta Targets.bmr(:female, 65.0, 165.0, 30), 1370.25, 0.001
    end
  end

  test "tdee applies the activity multiplier" do
    assert_in_delta Targets.tdee(2000.0, :sedentary), 2400.0, 0.001
    assert_in_delta Targets.tdee(2000.0, :moderate), 3100.0, 0.001
    assert_in_delta Targets.tdee(2000.0, :very_active), 3800.0, 0.001
  end

  test "goal_kcal adjusts by the flat rate" do
    assert Targets.goal_kcal(2500.0, :maintain, 400) == 2500
    assert Targets.goal_kcal(2500.0, :cut, 400) == 2100
    assert Targets.goal_kcal(2500.0, :bulk, 300) == 2800
  end

  test "macros: protein by bodyweight, fat by percent, carbs the remainder" do
    # 90kg @ 2.0 g/kg = 180g protein (720 kcal)
    # 2400 kcal @ 25% fat = 600 kcal / 9 = 67g
    # carbs = (2400 - 720 - 603) / 4 = 269
    macros = Targets.macros(2400, 90.0, 2.0, 25.0)

    assert macros.protein_g == 180
    assert macros.fat_g == 67
    assert macros.carbs_g == round((2400 - 180 * 4 - 67 * 9) / 4)
  end

  test "macros floors carbs at zero for very low calorie targets" do
    macros = Targets.macros(800, 100.0, 2.5, 30.0)
    assert macros.carbs_g >= 0
  end

  describe "compute/3" do
    defp profile(overrides \\ %{}) do
      Map.merge(
        %{
          height_cm: Decimal.new(180),
          birthdate: ~D[1991-03-15],
          sex: :male,
          activity_level: :moderate,
          goal: :cut,
          goal_rate_kcal_per_day: 400,
          protein_g_per_kg: Decimal.new("2.0"),
          fat_pct: Decimal.new(25),
          override_kcal: nil,
          override_protein_g: nil,
          override_fat_g: nil,
          override_carbs_g: nil
        },
        overrides
      )
    end

    test "chains bmr -> tdee -> goal -> macros" do
      {:ok, computed} = Targets.compute(profile(), 90.0, ~D[2026-07-11])

      # age 35 (birthday passed): bmr 1855, tdee 1855*1.55 = 2875.25, cut 400 -> 2475
      assert computed.bmr == 1855
      assert computed.tdee == 2875
      assert computed.kcal == 2475
      assert computed.protein_g == 180
    end

    test "age is exact around birthdays" do
      assert Targets.age_years(~D[1991-07-12], ~D[2026-07-11]) == 34
      assert Targets.age_years(~D[1991-07-11], ~D[2026-07-11]) == 35
    end

    test "missing body inputs -> incomplete_profile" do
      assert {:error, :incomplete_profile} =
               Targets.compute(profile(%{sex: nil}), 90.0, ~D[2026-07-11])
    end
  end

  describe "resolve/2" do
    test "overrides win per-field over computed" do
      profile = %{
        override_kcal: 2200,
        override_protein_g: nil,
        override_fat_g: nil,
        override_carbs_g: nil
      }

      computed = %{kcal: 2475, protein_g: 180, fat_g: 69, carbs_g: 285}

      assert {:ok, resolved} = Targets.resolve(profile, computed)
      assert resolved.kcal == 2200
      assert resolved.protein_g == 180
    end

    test "all-overrides works with nil computed" do
      profile = %{
        override_kcal: 2200,
        override_protein_g: 170,
        override_fat_g: 60,
        override_carbs_g: 240
      }

      assert {:ok, resolved} = Targets.resolve(profile, nil)
      assert resolved.carbs_g == 240
    end

    test "missing field with nil computed -> incomplete_targets" do
      profile = %{
        override_kcal: 2200,
        override_protein_g: nil,
        override_fat_g: 60,
        override_carbs_g: 240
      }

      assert {:error, :incomplete_targets} = Targets.resolve(profile, nil)
    end
  end
end
