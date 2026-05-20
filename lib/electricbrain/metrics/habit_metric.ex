defmodule Electricbrain.Metrics.HabitMetric do
  @moduledoc """
  Join between `Habits.Habit` and `Metrics.Metric`. A habit can capture
  multiple metrics on completion (Deadlift 1RM/3RM/8RM), and a metric can
  be fed by multiple habits (Calories captured from "log lunch" and
  "log dinner").
  """

  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Metrics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "habit_metrics"
    repo Electricbrain.Repo

    references do
      reference :habit, on_delete: :delete
      reference :metric, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:habit_id, :metric_id]
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

    validate {Electricbrain.Validations.OwnedParent,
              parent: Electricbrain.Metrics.Metric, field: :metric_id},
             on: [:create]
  end

  attributes do
    uuid_primary_key :id

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

    belongs_to :metric, Electricbrain.Metrics.Metric do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_habit_metric, [:habit_id, :metric_id]
  end
end
