defmodule Electricbrain.Metrics.Metric do
  @moduledoc """
  A user-defined numeric series — weight, deadlift 1RM, water drunk,
  alcoholic drinks. Each metric has a unit and an aggregation strategy
  that determines how multiple measurements in the same period combine:

    * `:point` — latest value wins per period (weight, 1RM)
    * `:sum`   — values add up per period (water, calories, drinks)

  Related metrics can share a `group_name` so they cluster on one chart
  (Deadlift 1RM/3RM/8RM share `group_name: "Deadlift"`).

  An optional flat goal (`goal_kind` + `goal_value`) drives the
  yellow-brick-road line on the chart and the on-track / off-track pill.
  `period` is the bucket size — required for `:sum` metrics (each bucket
  is summed and compared to the goal) and required whenever any goal is
  set (so the "current period" is well-defined for the status pill).
  Slope/rate goals are deferred to a future ship.
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
      accept [
        :name,
        :unit,
        :aggregation,
        :group_name,
        :category_id,
        :period,
        :goal_kind,
        :goal_value
      ]

      change relate_actor(:user)
    end

    update :update do
      accept [
        :name,
        :unit,
        :aggregation,
        :group_name,
        :category_id,
        :period,
        :goal_kind,
        :goal_value
      ]

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
    validate {__MODULE__.GoalConsistency, []}
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

    attribute :period, :atom do
      allow_nil? true
      public? true
      constraints one_of: [:day, :week, :month]
    end

    attribute :goal_kind, :atom do
      allow_nil? true
      public? true
      constraints one_of: [:at_least, :at_most]
    end

    attribute :goal_value, :decimal do
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
