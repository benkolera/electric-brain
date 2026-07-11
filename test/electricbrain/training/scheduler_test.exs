defmodule Electricbrain.Training.SchedulerTest do
  use Electricbrain.DataCase, async: true

  alias Electricbrain.Training
  alias Electricbrain.Training.Scheduler

  # Brisbane = UTC+10, no DST. Mon 2026-07-13 06:30 local = 2026-07-12 20:30 UTC.
  @tz "Australia/Brisbane"
  @monday_630 ~U[2026-07-12 20:30:00Z]

  defp setup_user! do
    user = create_user!()

    user =
      user
      |> Ash.Changeset.for_update(:set_timezone, %{timezone: @tz}, actor: user)
      |> Ash.update!(authorize?: false)

    :ok = Training.ensure_setup!(user)
    # Default settings: Mon/Wed/Fri at 06:30.
    _settings = Training.settings_for(user)
    user
  end

  test "fires once on a training day at the reminder time, with the prescription" do
    user = setup_user!()

    assert Scheduler.run_once(@monday_630) == 1
    assert Scheduler.run_once(@monday_630) == 0

    settings = Training.settings_for(user)
    assert settings.last_reminded_on == ~D[2026-07-13]
  end

  test "quiet on rest days and outside the window" do
    _user = setup_user!()

    # Tuesday 06:30 local — not a training day.
    assert Scheduler.run_once(~U[2026-07-13 20:30:00Z]) == 0

    # Monday, but two hours early.
    assert Scheduler.run_once(~U[2026-07-12 18:30:00Z]) == 0
  end

  test "skips when the user already trained (or is training) that local day" do
    user = setup_user!()

    # A completed workout earlier that same local Monday (05:00 Brisbane).
    Ash.Seed.seed!(Electricbrain.Training.Workout, %{
      user_id: user.id,
      status: :completed,
      template_name: "A",
      started_at: ~U[2026-07-12 19:00:00Z],
      ended_at: ~U[2026-07-12 20:00:00Z]
    })

    assert Scheduler.run_once(@monday_630) == 0

    settings = Training.settings_for(user)
    assert is_nil(settings.last_reminded_on)
  end
end
