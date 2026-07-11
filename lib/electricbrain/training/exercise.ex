defmodule Electricbrain.Training.Exercise do
  @moduledoc """
  A movement in the user's pool with its progression parameters.
  Per-user rows (seeded from `Training.Defaults` on first visit, then
  freely editable) — not a shared global library.

  `progression` drives the engine and defines the accessory pool:

    * `:weight` — barbell model: add `increment_kg` per successful
      session, deload `deload_pct`% after `stall_threshold`
      consecutive fails
    * `:reps` — accessory model: add a rep per successful session up
      to `rep_ceiling`; then, with `increment_kg` set (kettlebells —
      the next bell size), bump the weight and reset to `start_reps`;
      with it nil (bodyweight), keep adding reps

  `top_set_metric_id` / `e1rm_metric_id` are the auto-created Metrics
  series the completion pipeline logs into — explicit ids, not
  by-name lookup (renaming a metric must not fork a new series).
  """

  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Training,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "training_exercises"
    repo Electricbrain.Repo

    references do
      reference :top_set_metric, on_delete: :nilify
      reference :e1rm_metric, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :name,
        :kind,
        :progression,
        :increment_kg,
        :start_reps,
        :rep_ceiling,
        :deload_pct,
        :stall_threshold,
        :rest_seconds
      ]

      change relate_actor(:user)
    end

    update :update do
      accept [
        :name,
        :kind,
        :progression,
        :increment_kg,
        :start_reps,
        :rep_ceiling,
        :deload_pct,
        :stall_threshold,
        :rest_seconds
      ]

      require_atomic? false
    end

    # Completion-pipeline internal: persists the auto-created Metrics
    # series ids. Called authorize?: false.
    update :link_metrics do
      accept [:top_set_metric_id, :e1rm_metric_id]
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
              parent: Electricbrain.Metrics.Metric, field: :top_set_metric_id} do
      where changing(:top_set_metric_id)
    end

    validate {Electricbrain.Validations.OwnedParent,
              parent: Electricbrain.Metrics.Metric, field: :e1rm_metric_id} do
      where changing(:e1rm_metric_id)
    end

    validate compare(:stall_threshold, greater_than: 0) do
      where changing(:stall_threshold)
    end

    validate compare(:deload_pct, greater_than: 0, less_than: 100) do
      where changing(:deload_pct)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :kind, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:barbell, :kettlebell, :bodyweight]
    end

    attribute :progression, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:weight, :reps]
    end

    attribute :increment_kg, :decimal do
      allow_nil? true
      public? true
    end

    attribute :start_reps, :integer do
      allow_nil? true
      public? true
    end

    attribute :rep_ceiling, :integer do
      allow_nil? true
      public? true
    end

    attribute :deload_pct, :decimal do
      allow_nil? false
      default Decimal.new(10)
      public? true
    end

    attribute :stall_threshold, :integer do
      allow_nil? false
      default 3
      public? true
    end

    attribute :rest_seconds, :integer do
      allow_nil? true
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Electricbrain.Accounts.User do
      allow_nil? false
    end

    belongs_to :top_set_metric, Electricbrain.Metrics.Metric do
      allow_nil? true
      public? true
    end

    belongs_to :e1rm_metric, Electricbrain.Metrics.Metric do
      allow_nil? true
      public? true
    end

    has_one :state, Electricbrain.Training.ExerciseState
  end

  identities do
    identity :unique_name_per_user, [:user_id, :name]
  end
end
