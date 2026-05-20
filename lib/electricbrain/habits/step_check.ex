defmodule Electricbrain.Habits.StepCheck do
  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Habits,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "habit_step_checks"
    repo Electricbrain.Repo

    references do
      reference :completion, on_delete: :delete
      reference :ritual_step, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:completion_id, :ritual_step_id, :checked_at]
      change relate_actor(:user)
      change set_attribute(:checked_at, &DateTime.utc_now/0), where: [absent(:checked_at)]
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type([:read, :destroy]) do
      authorize_if relates_to_actor_via(:user)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :checked_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Electricbrain.Accounts.User do
      allow_nil? false
    end

    belongs_to :completion, Electricbrain.Habits.Completion do
      allow_nil? false
      public? true
    end

    belongs_to :ritual_step, Electricbrain.Habits.RitualStep do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_check, [:completion_id, :ritual_step_id]
  end
end
