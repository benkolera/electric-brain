defmodule Electricbrain.Metrics.Measurement do
  @moduledoc """
  A single recorded value for a `Metric`. Either entered manually (with a
  user-chosen `recorded_at`, typically backfill or "now") or captured at
  habit completion time, in which case `completion_id` links back to the
  `Habits.Completion` that produced it.
  """

  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Metrics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "measurements"
    repo Electricbrain.Repo

    references do
      reference :metric, on_delete: :delete
      reference :completion, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:metric_id, :value, :recorded_at, :completion_id]
      change relate_actor(:user)
      change set_attribute(:recorded_at, &DateTime.utc_now/0), where: [absent(:recorded_at)]
    end

    update :update do
      accept [:value, :recorded_at]
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
    validate {Electricbrain.Validations.NotFuture, field: :recorded_at}

    validate {Electricbrain.Validations.OwnedParent,
              parent: Electricbrain.Metrics.Metric, field: :metric_id},
             on: [:create]
  end

  attributes do
    uuid_primary_key :id

    attribute :value, :decimal do
      allow_nil? false
      public? true
    end

    attribute :recorded_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Electricbrain.Accounts.User do
      allow_nil? false
    end

    belongs_to :metric, Electricbrain.Metrics.Metric do
      allow_nil? false
      public? true
    end

    belongs_to :completion, Electricbrain.Habits.Completion do
      allow_nil? true
      public? true
    end
  end
end
