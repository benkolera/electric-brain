defmodule Electricbrain.Todos.Availability do
  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Todos,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "todo_availabilities"
    repo Electricbrain.Repo

    references do
      reference :todo, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:todo_id, :day_of_week, :start_time, :end_time]
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
    validate compare(:end_time, greater_than: :start_time),
      message: "end time must be after start time"

    validate {Electricbrain.Validations.OwnedParent,
              parent: Electricbrain.Todos.Todo, field: :todo_id},
             on: [:create]
  end

  attributes do
    uuid_primary_key :id

    attribute :day_of_week, :integer do
      allow_nil? false
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

    belongs_to :todo, Electricbrain.Todos.Todo do
      allow_nil? false
      public? true
    end
  end
end
