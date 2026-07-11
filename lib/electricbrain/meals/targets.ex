defmodule Electricbrain.Meals.Targets do
  @moduledoc """
  Pure calorie/macro target math.

  BMR via Mifflin-St Jeor, TDEE via a standard activity multiplier,
  goal adjustment as a flat kcal/day deficit or surplus, then the
  macro split: protein by bodyweight (g/kg), fat as a percentage of
  calories, carbs the remainder. `resolve/2` applies the profile's
  per-field manual overrides on top of the computed values.
  """

  @activity_multipliers %{
    sedentary: 1.2,
    light: 1.375,
    moderate: 1.55,
    active: 1.725,
    very_active: 1.9
  }

  @type targets :: %{
          kcal: integer(),
          protein_g: integer(),
          fat_g: integer(),
          carbs_g: integer()
        }

  @doc "Mifflin-St Jeor basal metabolic rate, kcal/day."
  def bmr(:male, weight_kg, height_cm, age_years),
    do: 10.0 * weight_kg + 6.25 * height_cm - 5.0 * age_years + 5.0

  def bmr(:female, weight_kg, height_cm, age_years),
    do: 10.0 * weight_kg + 6.25 * height_cm - 5.0 * age_years - 161.0

  def tdee(bmr, activity_level), do: bmr * Map.fetch!(@activity_multipliers, activity_level)

  def goal_kcal(tdee, :maintain, _rate), do: round(tdee)
  def goal_kcal(tdee, :cut, rate), do: round(tdee - rate)
  def goal_kcal(tdee, :bulk, rate), do: round(tdee + rate)

  @doc """
  Macro split for a calorie target: protein from bodyweight, fat from
  the percentage of calories (9 kcal/g), carbs from what's left
  (4 kcal/g, floored at zero).
  """
  def macros(kcal, weight_kg, protein_g_per_kg, fat_pct) do
    protein_g = round(weight_kg * protein_g_per_kg)
    fat_g = round(kcal * (fat_pct / 100.0) / 9.0)
    carbs_g = round(max(kcal - protein_g * 4 - fat_g * 9, 0) / 4.0)

    %{kcal: kcal, protein_g: protein_g, fat_g: fat_g, carbs_g: carbs_g}
  end

  @doc """
  Full computation from a profile + current weight. Returns
  `{:ok, %{bmr, tdee, kcal, protein_g, fat_g, carbs_g, basis}}` or
  `{:error, :incomplete_profile}` when height/birthdate/sex are
  missing (weight is the caller's job — see `Meals.Weight`).

  Pass `observed_tdee:` (e.g. an Oura trailing average) to replace the
  formula's `bmr × activity_multiplier` with a measured burn — `basis`
  reports `:observed` vs `:formula`, and the body inputs become
  optional since only the macro split still needs them.
  """
  def compute(profile, weight_kg, today, opts \\ []) do
    observed_tdee = Keyword.get(opts, :observed_tdee)

    complete? =
      not (is_nil(profile.height_cm) or is_nil(profile.birthdate) or is_nil(profile.sex))

    bmr =
      if complete? do
        age = age_years(profile.birthdate, today)
        bmr(profile.sex, weight_kg, to_float(profile.height_cm), age)
      end

    tdee =
      cond do
        observed_tdee -> observed_tdee * 1.0
        bmr -> tdee(bmr, profile.activity_level)
        true -> nil
      end

    if is_nil(tdee) do
      {:error, :incomplete_profile}
    else
      kcal = goal_kcal(tdee, profile.goal, profile.goal_rate_kcal_per_day)

      split =
        macros(kcal, weight_kg, to_float(profile.protein_g_per_kg), to_float(profile.fat_pct))

      {:ok,
       Map.merge(split, %{
         bmr: bmr && round(bmr),
         tdee: round(tdee),
         basis: if(observed_tdee, do: :observed, else: :formula)
       })}
    end
  end

  @doc """
  Applies the profile's manual overrides on top of computed targets
  (pass `nil` computed when there's no weight to compute from). Each
  target field resolves independently; returns
  `{:error, :incomplete_targets}` if any field has neither a computed
  value nor an override.
  """
  def resolve(profile, computed) do
    fields = [
      kcal: profile.override_kcal,
      protein_g: profile.override_protein_g,
      fat_g: profile.override_fat_g,
      carbs_g: profile.override_carbs_g
    ]

    resolved =
      Map.new(fields, fn {key, override} ->
        {key, override || (computed && computed[key])}
      end)

    if Enum.any?(resolved, fn {_, v} -> is_nil(v) end) do
      {:error, :incomplete_targets}
    else
      {:ok, resolved}
    end
  end

  def age_years(birthdate, today) do
    years = today.year - birthdate.year

    had_birthday? =
      {today.month, today.day} >= {birthdate.month, birthdate.day}

    if had_birthday?, do: years, else: years - 1
  end

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_number(n), do: n * 1.0
end
