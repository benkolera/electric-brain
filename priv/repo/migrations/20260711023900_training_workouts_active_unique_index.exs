defmodule Electricbrain.Repo.Migrations.TrainingWorkoutsActiveUniqueIndex do
  @moduledoc """
  Manual migration (no snapshot): partial unique index guaranteeing a
  user has at most one `:active` workout at a time. The app-layer
  validation `Electricbrain.Training.Validations.OneActivePerUser`
  produces a friendlier error first; this index is the last-line
  race-condition guard. Mirrors the focus_sessions precedent.
  """

  use Ecto.Migration

  def up do
    create unique_index(
             :training_workouts,
             [:user_id],
             where: "status = 'active'",
             name: "training_workouts_one_active_per_user"
           )
  end

  def down do
    drop_if_exists index(:training_workouts, [:user_id],
                     name: "training_workouts_one_active_per_user"
                   )
  end
end
