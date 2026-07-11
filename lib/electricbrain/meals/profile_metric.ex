defmodule Electricbrain.Meals.ProfileMetric do
  @moduledoc """
  Links a nutrition profile to a feedback metric (weight, waist, body
  fat %, key lifts — ordinary Metrics series) for the progress panel
  on `/meals`. Same cross-domain join shape as `Habits.HabitMetric`.
  `position` is the display order.
  """

  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Meals,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "profile_metrics"
    repo Electricbrain.Repo

    references do
      reference :nutrition_profile, on_delete: :delete
      reference :metric, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:nutrition_profile_id, :metric_id, :position]

      change relate_actor(:user)
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
              parent: Electricbrain.Meals.NutritionProfile, field: :nutrition_profile_id} do
      where changing(:nutrition_profile_id)
    end

    validate {Electricbrain.Validations.OwnedParent,
              parent: Electricbrain.Metrics.Metric, field: :metric_id} do
      where changing(:metric_id)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :position, :integer do
      allow_nil? false
      default 0
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :nutrition_profile, Electricbrain.Meals.NutritionProfile do
      allow_nil? false
      public? true
    end

    belongs_to :metric, Electricbrain.Metrics.Metric do
      allow_nil? false
      public? true
    end

    belongs_to :user, Electricbrain.Accounts.User do
      allow_nil? false
    end
  end

  identities do
    identity :unique_per_profile, [:nutrition_profile_id, :metric_id]
  end
end
