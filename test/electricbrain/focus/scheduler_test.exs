defmodule Electricbrain.Focus.SchedulerTest do
  # async: false — Scheduler is a singleton GenServer with mutable global
  # state, and we toggle the focus_minute_ms config below.
  use Electricbrain.DataCase, async: false

  # The Scheduler can race a finishing test's Ecto sandbox owner —
  # capture noisy DBConnection logs so they only surface on failure.
  @moduletag capture_log: true

  alias Electricbrain.Focus.Scheduler
  alias Electricbrain.Focus.Session

  setup do
    # Let the supervised Scheduler use this test's sandbox checkout.
    Ecto.Adapters.SQL.Sandbox.allow(
      Electricbrain.Repo,
      self(),
      Process.whereis(Scheduler)
    )

    # Drop timers from any prior test — without this the Scheduler
    # would fire against the (already gone) prior owner's connection
    # and spew DBConnection errors before our try/rescue catches it.
    Scheduler.clear_all_timers()

    user = create_user!()
    on_exit(fn -> Scheduler.clear_all_timers() end)
    {:ok, user: user}
  end

  defp start_session!(user, attrs) do
    Session
    |> Ash.Changeset.for_create(:start, attrs, actor: user)
    |> Ash.create!()
  end

  defp wait_for_status(session_id, expected, timeout_ms \\ 500) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait(session_id, expected, deadline)
  end

  defp do_wait(session_id, expected, deadline) do
    {:ok, session} = Ash.get(Session, session_id, authorize?: false)

    cond do
      session.status == expected ->
        session

      System.monotonic_time(:millisecond) > deadline ->
        flunk("status #{inspect(session.status)} != #{inspect(expected)} within timeout")

      true ->
        Process.sleep(5)
        do_wait(session_id, expected, deadline)
    end
  end

  test "arming on create fires :start_break when work elapses", %{user: user} do
    # 1 minute * 10ms = 10ms work, 1 * 10 = 10ms break.
    session = start_session!(user, %{duration_minutes: 1, break_minutes: 1})

    assert Scheduler.armed?(session.id)

    after_work = wait_for_status(session.id, :on_break)
    assert after_work.break_started_at
  end

  test "work then break fires :complete", %{user: user} do
    session = start_session!(user, %{duration_minutes: 1, break_minutes: 1})

    _ = wait_for_status(session.id, :on_break)
    after_break = wait_for_status(session.id, :completed)

    assert after_break.ended_at
    refute Scheduler.armed?(session.id)
  end

  test "abandoning disarms the timer", %{user: user} do
    session = start_session!(user, %{duration_minutes: 60, break_minutes: 5})
    assert Scheduler.armed?(session.id)

    session
    |> Ash.Changeset.for_update(:abandon, %{}, actor: user)
    |> Ash.update!()

    # Track ran -> Scheduler.track(:abandoned) cancels the timer.
    refute Scheduler.armed?(session.id)
  end

  test "broadcasts to the user's topic on each transition", %{user: user} do
    Phoenix.PubSub.subscribe(Electricbrain.PubSub, Scheduler.topic(user.id))

    session = start_session!(user, %{duration_minutes: 1, break_minutes: 1})

    assert_receive {:focus_session, %Session{id: id, status: :running}}, 200
    assert id == session.id

    assert_receive {:focus_session, %Session{status: :on_break}}, 500
    assert_receive {:focus_session, %Session{status: :completed}}, 500
  end
end
