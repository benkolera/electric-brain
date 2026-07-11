defmodule Electricbrain.Meals.Scheduler do
  @moduledoc """
  Singleton GenServer ticking once a minute for the meal-planning
  reminders, mirroring `Electricbrain.Notifications.Scheduler`:

    * **Meal times** — a push at each confirmed PlannedMeal's slot
      time ("Lunch — Chicken rice · 1.5 servings"), idempotent via
      `notified_at`.
    * **Saturday shopping** — at the profile's shopping reminder time:
      "list ready" when next week is confirmed
      (`shopping_notified_at`), otherwise a generate-your-plan nudge
      (idempotent via `profile.last_nudged_on`).
    * **Sunday prep** — at the prep reminder time, listing the week's
      dishes (`prep_notified_at`).

  All times are the user's local wall clock (profile `:time` fields in
  `user.timezone`). Set `:meals, :enabled` to false in test env.
  """

  use GenServer
  require Logger
  require Ash.Query

  alias Electricbrain.Meals.MealWeek
  alias Electricbrain.Meals.NutritionProfile
  alias Electricbrain.Meals.PlannedMeal
  alias Electricbrain.Notifications.Push

  @tick_ms 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    if enabled?() do
      schedule_tick(@tick_ms)
    end

    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    try do
      run_once()
    rescue
      err -> Logger.error("Meals.Scheduler tick crashed: #{Exception.message(err)}")
    end

    schedule_tick(@tick_ms)
    {:noreply, state}
  end

  @doc """
  One pass over due reminders. Public so tests and remote-IEx can poke
  it. Returns the number of pushes fired.
  """
  def run_once(now \\ DateTime.utc_now()) do
    profiles = load_profiles()

    oura_syncs(now, profiles)

    meal_reminders(now, profiles) + weekend_reminders(now, profiles)
  end

  # Daily Oura pull at ~06:00 local per connected user. Idempotent
  # (measurements upsert per day), so a double-fire inside the lead
  # window is harmless.
  @oura_sync_time ~T[06:00:00]

  defp oura_syncs(now, profiles) do
    profiles
    |> Map.values()
    |> Enum.filter(&Electricbrain.Oura.connected?(&1.user))
    |> Enum.each(fn profile ->
      local_date = now |> DateTime.shift_zone!(profile.user.timezone) |> DateTime.to_date()

      if due?(local_date, @oura_sync_time, profile.user.timezone, now) do
        case Electricbrain.Oura.Sync.sync_user(profile.user) do
          {:ok, _count} -> :ok
          {:error, reason} -> Logger.warning("Oura daily sync failed: #{inspect(reason)}")
        end
      end
    end)
  end

  # --- meal-time reminders ---------------------------------------------

  defp meal_reminders(now, profiles) do
    # Coarse date range in SQL (±1 day covers any timezone skew from
    # UTC "today"); exact slot-time window comparison happens in Elixir
    # — see Notifications.Scheduler for the timestamptz filter caveat.
    today = DateTime.to_date(now)
    from = Date.add(today, -1)
    to = Date.add(today, 1)

    PlannedMeal
    |> Ash.Query.filter(
      is_nil(notified_at) and meal_week.status == :confirmed and date >= ^from and date <= ^to
    )
    |> Ash.Query.load([:recipe, :user])
    |> Ash.read!(authorize?: false)
    |> Enum.reduce(0, fn meal, acc ->
      with %NutritionProfile{} = profile <- profiles[meal.user_id],
           true <- due?(meal.date, slot_time(profile, meal.slot), meal.user.timezone, now) do
        _ =
          Push.send_to_user(meal.user, %{
            title: "#{slot_title(meal.slot)} — #{meal.recipe.name}",
            body:
              "#{servings_str(meal.servings)} #{servings_word(meal.servings)} · " <>
                time_str(slot_time(profile, meal.slot)),
            url: "/meals"
          })

        meal
        |> Ash.Changeset.for_update(:mark_notified, %{}, authorize?: false)
        |> Ash.update!(authorize?: false)

        acc + 1
      else
        _ -> acc
      end
    end)
  end

  # --- Saturday shopping / Sunday prep ---------------------------------

  defp weekend_reminders(now, profiles) do
    profiles
    |> Map.values()
    |> Enum.reduce(0, fn profile, acc ->
      local_date = now |> DateTime.shift_zone!(profile.user.timezone) |> DateTime.to_date()

      case Date.day_of_week(local_date) do
        6 -> acc + shopping_reminder(profile, local_date, now)
        7 -> acc + prep_reminder(profile, local_date, now)
        _ -> acc
      end
    end)
  end

  defp shopping_reminder(profile, local_date, now) do
    user = profile.user

    if due?(local_date, profile.shopping_reminder_time, user.timezone, now) do
      week_start = Date.add(local_date, 2)

      case confirmed_week(user, week_start) do
        %MealWeek{shopping_notified_at: nil} = week ->
          _ =
            Push.send_to_user(user, %{
              title: "Shopping day",
              body: "Next week's list is ready — #{Calendar.strftime(week_start, "%d %b")}",
              url: "/meals/shopping"
            })

          week
          |> Ash.Changeset.for_update(:mark_shopping_notified, %{}, authorize?: false)
          |> Ash.update!(authorize?: false)

          1

        %MealWeek{} ->
          0

        nil ->
          nudge_to_plan(profile, local_date, week_start)
      end
    else
      0
    end
  end

  defp prep_reminder(profile, local_date, now) do
    user = profile.user

    with true <- due?(local_date, profile.prep_reminder_time, user.timezone, now),
         %MealWeek{prep_notified_at: nil} = week <- confirmed_week(user, Date.add(local_date, 1)) do
      _ =
        Push.send_to_user(user, %{
          title: "Meal prep day",
          body: prep_body(week),
          url: "/meals"
        })

      week
      |> Ash.Changeset.for_update(:mark_prep_notified, %{}, authorize?: false)
      |> Ash.update!(authorize?: false)

      1
    else
      _ -> 0
    end
  end

  defp nudge_to_plan(profile, local_date, week_start) do
    if profile.last_nudged_on == local_date do
      0
    else
      _ =
        Push.send_to_user(profile.user, %{
          title: "No meal plan yet",
          body:
            "Generate next week's plan (#{Calendar.strftime(week_start, "%d %b")}) and shop today",
          url: "/meals"
        })

      profile
      |> Ash.Changeset.for_update(:mark_nudged, %{last_nudged_on: local_date}, authorize?: false)
      |> Ash.update!(authorize?: false)

      1
    end
  end

  defp prep_body(week) do
    dishes =
      week.planned_meals
      |> Enum.reject(&(&1.slot == :shake))
      |> Enum.map(& &1.recipe.name)
      |> Enum.uniq()

    case dishes do
      [] -> "This week's meals are ready to prep"
      names -> "Prep: " <> Enum.join(names, ", ")
    end
  end

  defp confirmed_week(user, week_start) do
    case MealWeek
         |> Ash.Query.filter(user_id == ^user.id and week_start == ^week_start)
         |> Ash.Query.load(planned_meals: [:recipe])
         |> Ash.read_one!(authorize?: false) do
      %MealWeek{status: :confirmed} = week -> week
      _ -> nil
    end
  end

  # --- helpers ----------------------------------------------------------

  defp load_profiles do
    NutritionProfile
    |> Ash.Query.load(:user)
    |> Ash.read!(authorize?: false)
    |> Map.new(&{&1.user_id, &1})
  end

  # True when the local wall-clock instant (date + time in tz) falls
  # inside [now - 1min, now + lead].
  defp due?(date, time, timezone, now) do
    case DateTime.new(date, time, timezone) do
      {:ok, target} ->
        floor = DateTime.add(now, -60, :second)
        cutoff = DateTime.add(now, lead_minutes() * 60, :second)

        DateTime.compare(target, floor) != :lt and DateTime.compare(target, cutoff) != :gt

      _ ->
        false
    end
  end

  defp slot_time(profile, :breakfast), do: profile.breakfast_time
  defp slot_time(profile, :shake), do: profile.shake_time
  defp slot_time(profile, :lunch), do: profile.lunch_time
  defp slot_time(profile, :snack), do: profile.snack_time
  defp slot_time(profile, :dinner), do: profile.dinner_time

  defp slot_title(:breakfast), do: "Breakfast"
  defp slot_title(:shake), do: "Shake"
  defp slot_title(:lunch), do: "Lunch"
  defp slot_title(:snack), do: "Snack"
  defp slot_title(:dinner), do: "Dinner"

  defp servings_str(decimal), do: decimal |> Decimal.normalize() |> Decimal.to_string(:normal)

  defp servings_word(decimal),
    do: if(Decimal.equal?(decimal, 1), do: "serving", else: "servings")

  defp time_str(time), do: Calendar.strftime(time, "%H:%M")

  defp schedule_tick(ms), do: Process.send_after(self(), :tick, ms)

  defp config, do: Application.get_env(:electricbrain, :meals, [])

  defp lead_minutes, do: Keyword.get(config(), :lead_minutes, 5)

  defp enabled?, do: Keyword.get(config(), :enabled, true)
end
