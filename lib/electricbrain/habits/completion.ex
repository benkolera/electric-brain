defmodule Electricbrain.Habits.Completion do
  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Habits,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "habit_completions"
    repo Electricbrain.Repo

    references do
      reference :habit, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:habit_id, :completed_at]
      change relate_actor(:user)
      change set_attribute(:completed_at, &DateTime.utc_now/0), where: [absent(:completed_at)]
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

    attribute :completed_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Electricbrain.Accounts.User do
      allow_nil? false
    end

    belongs_to :habit, Electricbrain.Habits.Habit do
      allow_nil? false
      public? true
    end
  end
end
