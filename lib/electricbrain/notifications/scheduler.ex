defmodule Electricbrain.Notifications.Scheduler do
  @moduledoc """
  Singleton GenServer that ticks once a minute, finds planner entries whose
  start is within the next `lead_minutes` window and that haven't been
  notified yet, sends a push per entry, and marks the entry notified.

  Cron-driven so notifications fire reliably whether or not a user has an
  open browser session. One global actor for all users — small write
  volume and the SQL filter is indexed on `planned_at`.

  `lead_minutes` is configurable via:

      config :electricbrain, :notifications, lead_minutes: 5

  Set `:notifications, :enabled` to false in test envs to keep the
  scheduler quiet.
  """

  use GenServer
  require Logger
  require Ash.Query

  alias Electricbrain.Notifications.Push
  alias Electricbrain.Planner.Entry

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
      err -> Logger.error("Notifications.Scheduler tick crashed: #{Exception.message(err)}")
    end

    schedule_tick(@tick_ms)
    {:noreply, state}
  end

  @doc """
  One pass over due entries. Public so a test or a remote-IEx can poke it.
  Returns the number of notifications fired.
  """
  def run_once(now \\ DateTime.utc_now()) do
    lead = lead_minutes()
    cutoff = DateTime.add(now, lead * 60, :second)
    floor = DateTime.add(now, -1 * 60, :second)

    # NB: filter the time range in Elixir rather than via Ash.Query.filter.
    # The `planned_at` column is `timestamp without time zone`, and Ash's
    # filter generates a `::timestamptz` cast that's affected by the SQL
    # session's TimeZone setting — returning nothing when the session is
    # non-UTC. Loading the candidates (notified_at IS NULL) and filtering
    # in Elixir sidesteps that. The candidate set is tiny in practice.
    due =
      Entry
      |> Ash.Query.filter(not is_nil(planned_at) and is_nil(notified_at))
      |> Ash.Query.load([:todo, :habit, :time_block, :user])
      |> Ash.read!(authorize?: false)
      |> Enum.filter(fn entry ->
        DateTime.compare(entry.planned_at, floor) != :lt and
          DateTime.compare(entry.planned_at, cutoff) != :gt
      end)

    Enum.reduce(due, 0, fn entry, acc ->
      title = title_for(entry)

      payload = %{
        title: title,
        body: body_for(entry, now),
        url: "/"
      }

      _ = Push.send_to_user(entry.user, payload)

      entry
      |> Ash.Changeset.for_update(:mark_notified, %{}, authorize?: false)
      |> Ash.update!(authorize?: false)

      acc + 1
    end)
  end

  defp title_for(entry) do
    cond do
      entry.todo -> entry.todo.title
      entry.habit -> entry.habit.title
      entry.time_block -> entry.time_block.title
      true -> "Scheduled"
    end
  end

  defp body_for(entry, now) do
    minutes = div(max(DateTime.diff(entry.planned_at, now, :second), 0), 60)

    cond do
      minutes <= 0 -> "Starting now"
      minutes == 1 -> "Starts in 1 minute"
      true -> "Starts in #{minutes} minutes"
    end
  end

  defp schedule_tick(ms), do: Process.send_after(self(), :tick, ms)

  defp config, do: Application.get_env(:electricbrain, :notifications, [])

  defp lead_minutes, do: Keyword.get(config(), :lead_minutes, 5)

  defp enabled?, do: Keyword.get(config(), :enabled, true)
end
