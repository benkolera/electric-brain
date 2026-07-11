defmodule Electricbrain.Training.Scheduler do
  @moduledoc """
  Singleton GenServer ticking once a minute (the Meals.Scheduler
  shape): on a user's training day, at their local reminder time,
  push the next prescribed session — unless they've already trained
  (or are mid-workout) that local day. Idempotent once per day via
  `TrainingSettings.last_reminded_on`.

  Set `:training, :enabled` to false in test env.
  """

  use GenServer
  require Logger
  require Ash.Query

  alias Electricbrain.Notifications.Push
  alias Electricbrain.Training
  alias Electricbrain.Training.TrainingSettings
  alias Electricbrain.Training.Workout

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
      err -> Logger.error("Training.Scheduler tick crashed: #{Exception.message(err)}")
    end

    schedule_tick(@tick_ms)
    {:noreply, state}
  end

  @doc "One pass; returns the number of pushes fired. Public for tests/IEx."
  def run_once(now \\ DateTime.utc_now()) do
    TrainingSettings
    |> Ash.Query.load(:user)
    |> Ash.read!(authorize?: false)
    |> Enum.reduce(0, fn settings, acc ->
      acc + maybe_remind(settings, now)
    end)
  end

  defp maybe_remind(settings, now) do
    user = settings.user
    local_date = now |> DateTime.shift_zone!(user.timezone) |> DateTime.to_date()

    with true <- Date.day_of_week(local_date) in settings.training_days,
         true <- settings.last_reminded_on != local_date,
         true <- due?(local_date, settings.reminder_time, user.timezone, now),
         false <- trained_on?(user, local_date) do
      _ =
        Push.send_to_user(user, %{
          title: "Training day",
          body: session_body(user),
          url: "/training"
        })

      settings
      |> Ash.Changeset.for_update(:mark_reminded, %{last_reminded_on: local_date},
        authorize?: false
      )
      |> Ash.update!(authorize?: false)

      1
    else
      _ -> 0
    end
  end

  # Already trained (or mid-workout) that user-local day — skip.
  defp trained_on?(user, local_date) do
    day_start = DateTime.new!(local_date, ~T[00:00:00], user.timezone)
    day_end = DateTime.add(day_start, 86_400, :second)

    Workout
    |> Ash.Query.filter(user_id == ^user.id and status in [:active, :completed])
    |> Ash.read!(authorize?: false)
    |> Enum.any?(fn workout ->
      DateTime.compare(workout.started_at, day_start) != :lt and
        DateTime.compare(workout.started_at, day_end) == :lt
    end)
  end

  defp session_body(user) do
    case Training.next_session(user) do
      %{template: template, items: [first | _]} ->
        weight =
          case first.weight_kg do
            nil -> ""
            weight -> " @ #{weight |> Decimal.normalize() |> Decimal.to_string(:normal)} kg"
          end

        "Session #{template.name}: #{first.exercise_name} #{first.sets}×#{first.reps}#{weight}"

      _ ->
        "Time to train"
    end
  end

  # Same window logic as the meals scheduler: local wall-clock instant
  # within [now - 1min, now + lead].
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

  defp schedule_tick(ms), do: Process.send_after(self(), :tick, ms)

  defp config, do: Application.get_env(:electricbrain, :training, [])

  defp lead_minutes, do: Keyword.get(config(), :lead_minutes, 5)

  defp enabled?, do: Keyword.get(config(), :enabled, true)
end
