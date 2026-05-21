defmodule Electricbrain.Habits.Availability do
  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Habits,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "habit_availabilities"
    repo Electricbrain.Repo

    references do
      reference :habit, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:habit_id, :day_of_week, :start_time, :end_time]
      change relate_actor(:user)
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

  validations do
    validate {Electricbrain.Validations.OwnedParent,
              parent: Electricbrain.Habits.Habit, field: :habit_id},
             on: [:create]
  end

  attributes do
    uuid_primary_key :id

    # nil means "every day" — auto-prime expands into 1..7.
    attribute :day_of_week, :integer do
      public? true
      constraints min: 1, max: 7
    end

    attribute :start_time, :time do
      allow_nil? false
      public? true
    end

    attribute :end_time, :time do
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

  defdelegate duration_minutes(availability), to: Electricbrain.Availability
  defdelegate occurrences_per_week(availability), to: Electricbrain.Availability
end
