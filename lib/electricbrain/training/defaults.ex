defmodule Electricbrain.Training.Defaults do
  @moduledoc """
  The default exercise pool, A/B templates, and starting states seeded
  per-user by `Electricbrain.Training.ensure_setup!/1`. One source of
  truth so the seeder and the tests agree.

  All weights are kg (the training domain is kg-only). Barbell lifts
  progress by weight (+2.5 kg per successful session, +5 for deadlift,
  10% deload after 3 stalls); kettlebell and bodyweight movements
  progress by reps up to a ceiling — KB then jumps to the next bell
  size (+4 kg) and resets reps, bodyweight just keeps adding reps.
  """

  @exercises [
    %{
      name: "Back squat",
      kind: :barbell,
      progression: :weight,
      increment_kg: "2.5",
      start_weight_kg: "20"
    },
    %{
      name: "Deadlift",
      kind: :barbell,
      progression: :weight,
      increment_kg: "5",
      start_weight_kg: "40"
    },
    %{
      name: "Bench press",
      kind: :barbell,
      progression: :weight,
      increment_kg: "2.5",
      start_weight_kg: "20"
    },
    %{
      name: "Shoulder press",
      kind: :barbell,
      progression: :weight,
      increment_kg: "2.5",
      start_weight_kg: "20"
    },
    %{
      name: "Barbell row",
      kind: :barbell,
      progression: :weight,
      increment_kg: "2.5",
      start_weight_kg: "30"
    },
    %{
      name: "KB single-arm swings",
      kind: :kettlebell,
      progression: :reps,
      increment_kg: "4",
      start_reps: 10,
      rep_ceiling: 20,
      start_weight_kg: "16"
    },
    %{
      name: "KB turkish get-ups",
      kind: :kettlebell,
      progression: :reps,
      increment_kg: "4",
      start_reps: 3,
      rep_ceiling: 6,
      start_weight_kg: "16"
    },
    %{
      name: "KB sumo high pull",
      kind: :kettlebell,
      progression: :reps,
      increment_kg: "4",
      start_reps: 10,
      rep_ceiling: 20,
      start_weight_kg: "16"
    },
    %{name: "Pull ups", kind: :bodyweight, progression: :reps, start_reps: 5},
    %{name: "Ring dips", kind: :bodyweight, progression: :reps, start_reps: 5}
  ]

  @templates [
    %{
      name: "A",
      position: 0,
      slots: [
        %{position: 0, kind: :fixed, exercise: "Back squat", sets: 5, reps: 5},
        %{position: 1, kind: :fixed, exercise: "Bench press", sets: 5, reps: 5},
        %{position: 2, kind: :fixed, exercise: "Barbell row", sets: 5, reps: 5},
        %{position: 3, kind: :accessory, sets: 3},
        %{position: 4, kind: :accessory, sets: 3}
      ]
    },
    %{
      name: "B",
      position: 1,
      slots: [
        %{position: 0, kind: :fixed, exercise: "Back squat", sets: 5, reps: 5},
        %{position: 1, kind: :fixed, exercise: "Shoulder press", sets: 5, reps: 5},
        %{position: 2, kind: :fixed, exercise: "Deadlift", sets: 1, reps: 5},
        %{position: 3, kind: :accessory, sets: 3},
        %{position: 4, kind: :accessory, sets: 3}
      ]
    }
  ]

  def exercises, do: @exercises
  def templates, do: @templates
end
