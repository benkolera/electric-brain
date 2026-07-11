defmodule Electricbrain.Training.WorkoutSet do
  @moduledoc """
  One prescribed set in a workout, materialised at start from the
  generator's prescription. `actual_reps` nil means not done yet;
  tapping a set logs it at target reps (editable down). Exercise name
  and prescribed weight are snapshots so history survives later
  edits; progression reads targets vs actuals at completion.
  """

  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Training,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "training_workout_sets"
    repo Electricbrain.Repo

    references do
      reference :workout, on_delete: :delete
      reference :exercise, on_delete: :restrict
    end
  end

  actions do
    defaults [:read, :destroy]

    # Internal: bulk-created from the prescription at workout start.
    create :prescribe do
      accept [
        :workout_id,
        :exercise_id,
        :exercise_name,
        :position,
        :set_number,
        :slot_kind,
        :target_reps,
        :prescribed_weight_kg
      ]

      change relate_actor(:user)
    end

    update :log do
      accept [:actual_reps]
      require_atomic? false

      change set_attribute(:completed_at, &DateTime.utc_now/0)
      change Electricbrain.Training.Changes.Broadcast
    end

    update :unlog do
      accept []
      require_atomic? false

      change set_attribute(:actual_reps, nil)
      change set_attribute(:completed_at, nil)
      change Electricbrain.Training.Changes.Broadcast
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type([:read, :update, :destroy]) do
      authorize_if relates_to_actor_via(:user)
    end
  end

  validations do
    validate {Electricbrain.Validations.OwnedParent,
              parent: Electricbrain.Training.Workout, field: :workout_id} do
      where changing(:workout_id)
    end

    validate compare(:actual_reps, greater_than_or_equal_to: 0) do
      where changing(:actual_reps)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :exercise_name, :string do
      allow_nil? false
      public? true
    end

    attribute :position, :integer do
      allow_nil? false
      public? true
    end

    attribute :set_number, :integer do
      allow_nil? false
      public? true
    end

    attribute :slot_kind, :atom do
      allow_nil? false
      default :fixed
      public? true
      constraints one_of: [:fixed, :accessory]
    end

    attribute :target_reps, :integer do
      allow_nil? false
      public? true
    end

    attribute :prescribed_weight_kg, :decimal do
      allow_nil? true
      public? true
    end

    attribute :actual_reps, :integer do
      allow_nil? true
      public? true
    end

    attribute :completed_at, :utc_datetime_usec do
      allow_nil? true
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :workout, Electricbrain.Training.Workout do
      allow_nil? false
      public? true
    end

    belongs_to :exercise, Electricbrain.Training.Exercise do
      allow_nil? false
      public? true
    end

    belongs_to :user, Electricbrain.Accounts.User do
      allow_nil? false
    end
  end
end
