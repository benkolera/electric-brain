defmodule Electricbrain.Meals.SchedulerTest do
  use Electricbrain.DataCase, async: true

  require Ash.Query

  alias Electricbrain.Meals.Ingredient
  alias Electricbrain.Meals.NutritionProfile
  alias Electricbrain.Meals.Planning
  alias Electricbrain.Meals.Recipe
  alias Electricbrain.Meals.Scheduler

  # Brisbane = UTC+10, no DST. Week under test starts Mon 2026-07-13.
  @tz "Australia/Brisbane"
  @week_start ~D[2026-07-13]

  defp setup_user!(profile_attrs \\ %{}) do
    user = create_user!()

    user =
      user
      |> Ash.Changeset.for_update(:set_timezone, %{timezone: @tz}, actor: user)
      |> Ash.update!(authorize?: false)

    profile =
      NutritionProfile
      |> Ash.Changeset.for_create(
        :create,
        Map.merge(
          %{
            override_kcal: 2400,
            override_protein_g: 180,
            override_fat_g: 67,
            override_carbs_g: 270,
            max_shakes_per_day: 0,
            lunch_time: ~T[12:30:00],
            shopping_reminder_time: ~T[08:00:00],
            prep_reminder_time: ~T[09:00:00]
          },
          profile_attrs
        ),
        actor: user
      )
      |> Ash.create!()

    {user, profile}
  end

  defp seed_week!(user, opts \\ []) do
    base =
      Ingredient
      |> Ash.Changeset.for_create(
        :create,
        %{
          name: "Base food",
          kcal_per_100g: "450",
          protein_g_per_100g: "35",
          fat_g_per_100g: "10",
          carbs_g_per_100g: "20",
          fibre_g_per_100g: "0"
        },
        actor: user
      )
      |> Ash.create!()

    for {name, slot} <- [{"Oats bowl", :breakfast}, {"Chicken rice", :main}, {"Cups", :snack}] do
      Recipe
      |> Ash.Changeset.for_create(
        :create,
        %{
          name: name,
          slot_type: slot,
          servings: 1,
          recipe_ingredients: [%{ingredient_id: base.id, quantity_g: 100}]
        },
        actor: user
      )
      |> Ash.create!()
    end

    {:ok, week} = Planning.generate_week(user, @week_start)

    if Keyword.get(opts, :confirm, true) do
      Planning.confirm_week(user, week)
    else
      week
    end
  end

  # Monday 2026-07-13 12:30 Brisbane == 02:30 UTC.
  @monday_lunch ~U[2026-07-13 02:30:00Z]

  describe "meal-time reminders" do
    test "fires within the lead window and marks notified, exactly once" do
      {user, _profile} = setup_user!()
      seed_week!(user)

      # 3 minutes before lunch — inside the 5-minute lead.
      assert Scheduler.run_once(DateTime.add(@monday_lunch, -3 * 60)) == 1
      assert Scheduler.run_once(DateTime.add(@monday_lunch, -3 * 60)) == 0

      week = Planning.week_for(user, @week_start)
      lunch = Enum.find(week.planned_meals, &(&1.date == @week_start and &1.slot == :lunch))
      assert lunch.notified_at
    end

    test "does not fire outside the window" do
      {user, _profile} = setup_user!()
      seed_week!(user)

      assert Scheduler.run_once(DateTime.add(@monday_lunch, -30 * 60)) == 0
    end

    test "draft weeks never notify" do
      {user, _profile} = setup_user!()
      seed_week!(user, confirm: false)

      assert Scheduler.run_once(DateTime.add(@monday_lunch, -3 * 60)) == 0
    end
  end

  describe "Saturday shopping reminder" do
    # Saturday 2026-07-11 08:00 Brisbane == 2026-07-10 22:00 UTC.
    @saturday_8am ~U[2026-07-10 22:00:00Z]

    test "fires once when next week is confirmed" do
      {user, _profile} = setup_user!()
      seed_week!(user)

      assert Scheduler.run_once(@saturday_8am) == 1
      assert Scheduler.run_once(@saturday_8am) == 0

      week = Planning.week_for(user, @week_start)
      assert week.shopping_notified_at
    end

    test "nudges to generate when no confirmed plan, once per day" do
      {user, _profile} = setup_user!()

      assert Scheduler.run_once(@saturday_8am) == 1
      assert Scheduler.run_once(@saturday_8am) == 0

      profile = Electricbrain.Meals.profile_for(user)
      assert profile.last_nudged_on == ~D[2026-07-11]
    end

    test "quiet on non-Saturdays" do
      {user, _profile} = setup_user!()
      seed_week!(user)

      # Friday 08:00 Brisbane
      assert Scheduler.run_once(~U[2026-07-09 22:00:00Z]) == 0
    end
  end

  describe "Sunday prep reminder" do
    # Sunday 2026-07-12 09:00 Brisbane == 2026-07-11 23:00 UTC.
    @sunday_9am ~U[2026-07-11 23:00:00Z]

    test "fires once with the week's dishes" do
      {user, _profile} = setup_user!()
      seed_week!(user)

      assert Scheduler.run_once(@sunday_9am) == 1
      assert Scheduler.run_once(@sunday_9am) == 0

      week = Planning.week_for(user, @week_start)
      assert week.prep_notified_at
    end

    test "quiet without a confirmed week" do
      {user, _profile} = setup_user!()
      seed_week!(user, confirm: false)

      assert Scheduler.run_once(@sunday_9am) == 0
    end
  end
end
