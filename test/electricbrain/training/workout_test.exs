defmodule Electricbrain.Training.WorkoutTest do
  use Electricbrain.DataCase, async: true

  require Ash.Query

  alias Electricbrain.Metrics.Measurement
  alias Electricbrain.Metrics.Metric
  alias Electricbrain.Training
  alias Electricbrain.Training.MetricsLog
  alias Electricbrain.Training.Workout

  defp setup_user! do
    user = create_user!()
    :ok = Training.ensure_setup!(user)
    user
  end

  defp exercise!(user, name),
    do: Enum.find(Training.exercises_for(user), &(&1.name == name))

  defp log_all!(user, workout, opts \\ []) do
    miss = Keyword.get(opts, :miss, [])

    Enum.each(workout.sets, fn set ->
      actual =
        if set.exercise_name in miss and set.set_number == 1,
          do: set.target_reps - 1,
          else: set.target_reps

      set
      |> Ash.Changeset.for_update(:log, %{actual_reps: actual}, actor: user)
      |> Ash.update!()
    end)
  end

  describe "start_workout!/1" do
    test "materialises template A's prescription for a fresh user" do
      user = setup_user!()

      {:ok, workout} = Training.start_workout!(user)

      assert workout.status == :active
      assert workout.template_name == "A"

      by_exercise = Enum.group_by(workout.sets, & &1.exercise_name)
      assert length(by_exercise["Back squat"]) == 5
      assert length(by_exercise["Bench press"]) == 5
      assert length(by_exercise["Barbell row"]) == 5

      squat_set = hd(by_exercise["Back squat"])
      assert squat_set.target_reps == 5
      assert Decimal.equal?(squat_set.prescribed_weight_kg, Decimal.new(20))

      # 2 accessory slots × 3 sets from the reps pool.
      accessory_sets = Enum.filter(workout.sets, &(&1.slot_kind == :accessory))
      assert length(accessory_sets) == 6

      # Ordered positions cover the whole session.
      assert Enum.map(workout.sets, & &1.position) == Enum.to_list(0..(length(workout.sets) - 1))
    end

    test "only one active workout per user" do
      user = setup_user!()
      {:ok, _workout} = Training.start_workout!(user)

      assert_raise Ash.Error.Invalid, ~r/active workout/, fn ->
        Training.start_workout!(user)
      end
    end
  end

  describe "complete_workout!/2" do
    test "applies progression: passed lifts +increment, missed lifts stall" do
      user = setup_user!()
      {:ok, workout} = Training.start_workout!(user)
      log_all!(user, workout, miss: ["Bench press"])

      Training.complete_workout!(user, workout)

      squat = exercise!(user, "Back squat")
      assert Decimal.equal?(squat.state.current_weight_kg, Decimal.new("22.5"))
      assert squat.state.consecutive_stalls == 0

      bench = exercise!(user, "Bench press")
      assert Decimal.equal?(bench.state.current_weight_kg, Decimal.new(20))
      assert bench.state.consecutive_stalls == 1
    end

    test "accessories progress by reps" do
      user = setup_user!()
      {:ok, workout} = Training.start_workout!(user)

      accessory_names =
        workout.sets
        |> Enum.filter(&(&1.slot_kind == :accessory))
        |> Enum.map(& &1.exercise_name)
        |> Enum.uniq()

      log_all!(user, workout)
      Training.complete_workout!(user, workout)

      for name <- accessory_names do
        exercise = exercise!(user, name)

        start =
          Training.Defaults.exercises() |> Enum.find(&(&1.name == name)) |> Map.get(:start_reps)

        assert exercise.state.current_reps == start + 1
      end
    end

    test "template alternates only after completion" do
      user = setup_user!()
      {:ok, workout} = Training.start_workout!(user)
      log_all!(user, workout)
      Training.complete_workout!(user, workout)

      assert %{template: %{name: "B"}} = Training.next_session(user)
    end

    test "writes top-set and e1RM measurements, idempotently" do
      user = setup_user!()
      {:ok, workout} = Training.start_workout!(user)
      log_all!(user, workout)
      completed = Training.complete_workout!(user, workout)

      squat = exercise!(user, "Back squat")
      assert squat.top_set_metric_id
      assert squat.e1rm_metric_id

      top_metric = Ash.get!(Metric, squat.top_set_metric_id, actor: user)
      assert top_metric.unit == "kg"
      assert top_metric.group_name == "Back squat"

      [top] =
        Measurement
        |> Ash.Query.filter(metric_id == ^squat.top_set_metric_id)
        |> Ash.read!(actor: user)

      assert Decimal.equal?(top.value, Decimal.new(20))

      [e1rm] =
        Measurement
        |> Ash.Query.filter(metric_id == ^squat.e1rm_metric_id)
        |> Ash.read!(actor: user)

      # 20 × (1 + 5/30) = 23.33
      assert Decimal.equal?(e1rm.value, Decimal.new("23.33"))

      # Re-running the log is a no-op.
      completed = Ash.get!(Workout, completed.id, actor: user)
      assert MetricsLog.log_workout!(user, completed) == 0
    end

    test "accessories don't log metrics; second workout reuses the linked series" do
      user = setup_user!()

      {:ok, first} = Training.start_workout!(user)
      log_all!(user, first)
      Training.complete_workout!(user, first)

      swings = exercise!(user, "KB single-arm swings")
      assert is_nil(swings.top_set_metric_id)

      {:ok, second} = Training.start_workout!(user)
      log_all!(user, second)
      Training.complete_workout!(user, second)

      squat = exercise!(user, "Back squat")

      values =
        Measurement
        |> Ash.Query.filter(metric_id == ^squat.top_set_metric_id)
        |> Ash.read!(actor: user)
        |> Enum.map(&Decimal.to_float(&1.value))
        |> Enum.sort()

      # 20 then 22.5 on the same series.
      assert values == [20.0, 22.5]

      metric_count =
        Metric |> Ash.Query.filter(group_name == "Back squat") |> Ash.count!(actor: user)

      assert metric_count == 2
    end
  end

  describe "abandon_workout!/2" do
    test "applies nothing: no progression, no metrics, template repeats" do
      user = setup_user!()
      {:ok, workout} = Training.start_workout!(user)
      log_all!(user, workout)

      Training.abandon_workout!(user, workout)

      squat = exercise!(user, "Back squat")
      assert Decimal.equal?(squat.state.current_weight_kg, Decimal.new(20))
      assert is_nil(squat.top_set_metric_id)
      assert %{template: %{name: "A"}} = Training.next_session(user)
      assert is_nil(Training.active_workout(user))
    end
  end

  describe "set logging" do
    test "log stamps completed_at; unlog clears both" do
      user = setup_user!()
      {:ok, workout} = Training.start_workout!(user)
      set = hd(workout.sets)

      logged =
        set
        |> Ash.Changeset.for_update(:log, %{actual_reps: 5}, actor: user)
        |> Ash.update!()

      assert logged.actual_reps == 5
      assert logged.completed_at

      unlogged =
        logged
        |> Ash.Changeset.for_update(:unlog, %{}, actor: user)
        |> Ash.update!()

      assert is_nil(unlogged.actual_reps)
      assert is_nil(unlogged.completed_at)
    end
  end
end
