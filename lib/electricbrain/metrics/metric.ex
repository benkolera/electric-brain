defmodule Electricbrain.Metrics.Metric do
  @moduledoc """
  A user-defined numeric series — weight, deadlift 1RM, water drunk,
  alcoholic drinks. Each metric has a unit and an aggregation strategy
  that determines how multiple measurements in the same period combine:

    * `:point` — latest value wins per period (weight, 1RM)
    * `:sum`   — values add up per period (water, calories, drinks)

  Related metrics can share a `group_name` so they cluster on one chart
  (Deadlift 1RM/3RM/8RM share `group_name: "Deadlift"`).
  """

  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Metrics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "metrics"
    repo Electricbrain.Repo

    references do
      reference :category, on_delete: :restrict
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :unit, :aggregation, :group_name, :category_id]
      change relate_actor(:user)
    end

    update :update do
      accept [:name, :unit, :aggregation, :group_name, :category_id]
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

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :unit, :string do
      allow_nil? false
      public? true
    end

    attribute :aggregation, :atom do
      allow_nil? false
      default :point
      public? true
      constraints one_of: [:point, :sum]
    end

    attribute :group_name, :string do
      allow_nil? true
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Electricbrain.Accounts.User do
      allow_nil? false
    end

    belongs_to :category, Electricbrain.Categories.Category do
      allow_nil? true
      public? true
    end

    has_many :measurements, Electricbrain.Metrics.Measurement
    has_many :habit_links, Electricbrain.Metrics.HabitMetric
  end
end
