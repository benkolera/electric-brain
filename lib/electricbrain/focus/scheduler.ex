defmodule Electricbrain.Focus.Scheduler do
  @moduledoc """
  Singleton GenServer that fires the work-end and break-end transitions
  on focus sessions. Internal state: `%{session_id => timer_ref}`.

  The Track after-action on `Focus.Session` calls `track/1` after every
  create/update so this process always knows about the current state.
  We compute timer delays from `(session.started_at + duration_ms) - now`
  (or break analogue) so boot-time sweeps re-arm with the correct
  remaining time.

  Time is unit-converted via `:focus_minute_ms` (default 60_000). Tests
  set it to a small value so a 1-minute session fires in milliseconds.
  """

  use GenServer
  require Logger
  require Ash.Query

  alias Electricbrain.Accounts.User
  alias Electricbrain.Focus.Session
  alias Electricbrain.Notifications.Push

  @topic_prefix "focus:user:"

  ## Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Topic for a user's focus session broadcasts."
  def topic(user_id), do: @topic_prefix <> to_string(user_id)

  @doc """
  React to a session state change. Re-arms or disarms the timer based on
  the session's current status. Safe to call multiple times for the same
  session — internal state replaces any prior timer.
  """
  def track(%Session{} = session) do
    GenServer.cast(__MODULE__, {:track, session})
  end

  @doc "Test/introspection helper: is there a timer armed for this session?"
  def armed?(session_id) do
    GenServer.call(__MODULE__, {:armed?, session_id})
  end

  @doc "Test helper: cancel every armed timer."
  def clear_all_timers do
    GenServer.call(__MODULE__, :clear_all_timers)
  end

  ## GenServer

  @impl true
  def init(_opts) do
    # Sweep on boot — re-arm timers for any session that was active
    # when the previous BEAM stopped. Skipped in tests (and any other
    # env that doesn't want it) via `config :electricbrain, :focus_scheduler, sweep: false`.
    if sweep_on_boot?(), do: send(self(), :boot_sweep)
    {:ok, %{timers: %{}}}
  end

  @impl true
  def handle_info(:boot_sweep, state) do
    new_state =
      try do
        Session
        |> Ash.Query.filter(status in [:running, :on_break])
        |> Ash.read!(authorize?: false)
        |> Enum.reduce(state, &arm_for(&2, &1))
      rescue
        err ->
          Logger.warning("Focus boot_sweep failed: #{Exception.message(err)}")
          state
      end

    {:noreply, new_state}
  end

  def handle_info({:fire, session_id, kind}, state) do
    state = %{state | timers: Map.delete(state.timers, session_id)}

    # Wrap in a try — a stale timer from a now-gone Ecto sandbox owner
    # (test cleanup) would otherwise crash the Scheduler and bring the
    # supervisor down via restart-intensity.
    try do
      case Ash.get(Session, session_id, authorize?: false) do
        {:ok, session} -> fire(session, kind)
        _ -> :ok
      end
    rescue
      err -> Logger.warning("Focus fire failed for #{session_id}: #{Exception.message(err)}")
    catch
      :exit, reason ->
        Logger.warning("Focus fire exited for #{session_id}: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:track, session}, state), do: {:noreply, arm_for(state, session)}

  @impl true
  def handle_call({:armed?, session_id}, _from, state) do
    {:reply, Map.has_key?(state.timers, session_id), state}
  end

  def handle_call(:clear_all_timers, _from, state) do
    for {_id, ref} <- state.timers, do: Process.cancel_timer(ref)
    {:reply, :ok, %{state | timers: %{}}}
  end

  ## Internal

  defp arm_for(state, %Session{status: :running} = session) do
    delay = remaining_ms(session.started_at, session.duration_minutes)
    schedule(state, session.id, :work, delay)
  end

  defp arm_for(state, %Session{status: :on_break} = session) do
    delay = remaining_ms(session.break_started_at, session.break_minutes)
    schedule(state, session.id, :break, delay)
  end

  defp arm_for(state, %Session{} = session) do
    cancel(state, session.id)
  end

  defp schedule(state, session_id, kind, delay_ms) do
    state = cancel(state, session_id)
    ref = Process.send_after(self(), {:fire, session_id, kind}, max(0, delay_ms))
    %{state | timers: Map.put(state.timers, session_id, ref)}
  end

  defp cancel(state, session_id) do
    case Map.fetch(state.timers, session_id) do
      {:ok, ref} ->
        Process.cancel_timer(ref)
        %{state | timers: Map.delete(state.timers, session_id)}

      :error ->
        state
    end
  end

  defp remaining_ms(nil, _minutes), do: 0

  defp remaining_ms(started_at, minutes) do
    total_ms = minutes * minute_ms()
    elapsed_ms = DateTime.diff(DateTime.utc_now(), started_at, :millisecond)
    max(0, total_ms - elapsed_ms)
  end

  # When the timer fires we reload the session and check the status is
  # still what we expected — manual transitions ("Skip break", "Abandon")
  # may have raced us.
  defp fire(%Session{status: :running} = session, :work) do
    session
    |> Ash.Changeset.for_update(:start_break, %{}, authorize?: false)
    |> Ash.update()
    |> case do
      {:ok, _} -> push(session, "Time for a break", "Step away from the trellis.")
      {:error, reason} -> Logger.warning("Focus :start_break failed: #{inspect(reason)}")
    end
  end

  defp fire(%Session{status: :on_break} = session, :break) do
    session
    |> Ash.Changeset.for_update(:complete, %{}, authorize?: false)
    |> Ash.update()
    |> case do
      {:ok, _} -> push(session, "Back to focus", "Break's done — pick up where you left off.")
      {:error, reason} -> Logger.warning("Focus :complete failed: #{inspect(reason)}")
    end
  end

  defp fire(_session, _kind), do: :ok

  defp push(session, title, body) do
    case Ash.get(User, session.user_id, authorize?: false) do
      {:ok, user} -> Push.send_to_user(user, %{title: title, body: body, url: "/focus"})
      _ -> :ok
    end
  end

  defp minute_ms, do: Application.get_env(:electricbrain, :focus_minute_ms, 60_000)

  defp sweep_on_boot? do
    Application.get_env(:electricbrain, :focus_scheduler, [])
    |> Keyword.get(:sweep, true)
  end
end
