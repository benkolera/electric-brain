defmodule Electricbrain.Training.ExerciseState do
  @moduledoc """
  The progression cursor for one exercise: current working weight
  (weight mode), current target reps (reps mode), and the consecutive
  stall count. Workouts are the immutable audit trail; this row is
  what "next prescription" reads — cheap for the week view, the
  reminder push body, and the G2 payload, and directly editable as
  the starting-weights prompt / correction escape hatch.

  A user edit that changes the weight resets the stall count; the
  completion pipeline advances state via the internal `:advance`
  action (`authorize?: false`).
  """

  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Training,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "training_exercise_states"
    repo Electricbrain.Repo

    references do
      reference :exercise, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:exercise_id, :current_weight_kg, :current_reps]

      change relate_actor(:user)
    end

    # User edit from settings — changing the weight is a manual
    # correction, so the stall streak starts over.
    update :update do
      accept [:current_weight_kg, :current_reps]
      require_atomic? false

      change fn changeset, _context ->
        if Ash.Changeset.changing_attribute?(changeset, :current_weight_kg) do
          Ash.Changeset.change_attribute(changeset, :consecutive_stalls, 0)
        else
          changeset
        end
      end
    end

    # Completion-pipeline internal (authorize?: false).
    update :advance do
      accept [:current_weight_kg, :current_reps, :consecutive_stalls]
      require_atomic? false
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
              parent: Electricbrain.Training.Exercise, field: :exercise_id} do
      where changing(:exercise_id)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :current_weight_kg, :decimal do
      allow_nil? true
      public? true
    end

    attribute :current_reps, :integer do
      allow_nil? true
      public? true
    end

    attribute :consecutive_stalls, :integer do
      allow_nil? false
      default 0
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :exercise, Electricbrain.Training.Exercise do
      allow_nil? false
      public? true
    end

    belongs_to :user, Electricbrain.Accounts.User do
      allow_nil? false
    end
  end

  identities do
    identity :one_per_exercise, [:user_id, :exercise_id]
  end
end
