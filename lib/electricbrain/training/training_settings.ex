defmodule Electricbrain.Training.TrainingSettings do
  @moduledoc """
  One-per-user training preferences: which days to train (ISO day
  numbers), the user-local reminder time, and the default rest between
  sets (a per-exercise `rest_seconds` overrides it). Weights are
  kg-only across the training domain.

  `last_reminded_on` is the training-day reminder's idempotence mark
  (the meals `last_nudged_on` pattern) — there's no persisted session
  row to mark before the user actually starts training.
  """

  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Training,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "training_settings"
    repo Electricbrain.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:training_days, :reminder_time, :default_rest_seconds]

      change relate_actor(:user)
    end

    update :update do
      accept [:training_days, :reminder_time, :default_rest_seconds]
      require_atomic? false
    end

    # Scheduler-internal reminder idempotence (authorize?: false).
    update :mark_reminded do
      accept [:last_reminded_on]
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
    validate {Electricbrain.Training.Validations.ValidTrainingDays, []} do
      where changing(:training_days)
    end

    validate compare(:default_rest_seconds, greater_than: 0) do
      where changing(:default_rest_seconds)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :training_days, {:array, :integer} do
      allow_nil? false
      default [1, 3, 5]
      public? true
    end

    attribute :reminder_time, :time do
      allow_nil? false
      default ~T[06:30:00]
      public? true
    end

    attribute :default_rest_seconds, :integer do
      allow_nil? false
      default 180
      public? true
    end

    attribute :last_reminded_on, :date do
      allow_nil? true
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Electricbrain.Accounts.User do
      allow_nil? false
    end
  end

  identities do
    identity :one_per_user, [:user_id]
  end
end
