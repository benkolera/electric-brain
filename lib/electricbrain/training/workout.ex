defmodule Electricbrain.Training.Workout do
  @moduledoc """
  One gym session: `:active` while in the gym, then `:completed`
  (progression + metrics apply) or `:abandoned` (nothing applies).
  At most one active workout per user — app-layer validation plus a
  partial unique index (manual migration) as the hard guarantee,
  mirroring `Focus.Session`.

  `template_name` is snapshotted so history reads correctly after
  template edits; `metrics_logged_at` is the auto-log idempotence
  mark. Every create/update broadcasts `{:training_workout, workout}`
  on `Training.topic/1` (LiveView sync + G2 SSE wake).
  """

  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Training,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "training_workouts"
    repo Electricbrain.Repo

    references do
      reference :template, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy]

    create :start do
      accept [:template_id, :template_name]

      change relate_actor(:user)
      change set_attribute(:status, :active)
      change set_attribute(:started_at, &DateTime.utc_now/0)
      validate {Electricbrain.Training.Validations.OneActivePerUser, []}
      change Electricbrain.Training.Changes.Broadcast
    end

    update :complete do
      accept []
      require_atomic? false

      change set_attribute(:status, :completed)
      change set_attribute(:ended_at, &DateTime.utc_now/0)
      change Electricbrain.Training.Changes.Broadcast
    end

    update :abandon do
      accept []
      require_atomic? false

      change set_attribute(:status, :abandoned)
      change set_attribute(:ended_at, &DateTime.utc_now/0)
      change Electricbrain.Training.Changes.Broadcast
    end

    # Metrics auto-log idempotence (authorize?: false internal).
    update :mark_metrics_logged do
      accept []
      require_atomic? false

      change set_attribute(:metrics_logged_at, &DateTime.utc_now/0)
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

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      allow_nil? false
      default :active
      public? true
      constraints one_of: [:active, :completed, :abandoned]
    end

    attribute :template_name, :string do
      allow_nil? true
      public? true
    end

    attribute :started_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :ended_at, :utc_datetime_usec do
      allow_nil? true
      public? true
    end

    attribute :metrics_logged_at, :utc_datetime_usec do
      allow_nil? true
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Electricbrain.Accounts.User do
      allow_nil? false
    end

    belongs_to :template, Electricbrain.Training.Template do
      allow_nil? true
      public? true
    end

    has_many :sets, Electricbrain.Training.WorkoutSet do
      sort position: :asc
    end
  end
end
