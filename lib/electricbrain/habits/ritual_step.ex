defmodule Electricbrain.Habits.RitualStep do
  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Habits,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "habit_ritual_steps"
    repo Electricbrain.Repo

    references do
      reference :habit, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:habit_id, :title]
      change relate_actor(:user)
    end

    update :update do
      accept [:title]
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
              parent: Electricbrain.Habits.Habit, field: :habit_id},
             on: [:create]
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
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

    has_many :step_checks, Electricbrain.Habits.StepCheck
  end
end
