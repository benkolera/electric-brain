defmodule Electricbrain.Meals.NutritionProfile do
  @moduledoc """
  One-per-user meal planning settings: the body inputs that drive
  BMR/TDEE (Mifflin-St Jeor), the goal (cut/maintain/bulk at a
  kcal/day rate), the macro split, per-field target overrides, and
  the user-local eating/reminder times the meal scheduler fires at.

  Weight is NOT stored here — `weight_metric_id` points at the user's
  weight series in the Metrics domain, so the same number the metrics
  chart tracks feeds the targets. Overrides are nil-means-computed:
  a non-nil override_* wins over the computed value for that field
  (see `Electricbrain.Meals.Targets.resolve/2`).
  """

  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Meals,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "nutrition_profiles"
    repo Electricbrain.Repo

    references do
      reference :weight_metric, on_delete: :nilify
    end
  end

  @accepted [
    :height_cm,
    :birthdate,
    :sex,
    :activity_level,
    :goal,
    :goal_rate_kcal_per_day,
    :weight_metric_id,
    :protein_g_per_kg,
    :fat_pct,
    :override_kcal,
    :override_protein_g,
    :override_fat_g,
    :override_carbs_g,
    :breakfast_time,
    :shake_time,
    :lunch_time,
    :snack_time,
    :dinner_time,
    :shopping_reminder_time,
    :prep_reminder_time,
    :max_shakes_per_day
  ]

  actions do
    defaults [:read, :destroy]

    create :create do
      accept @accepted

      change relate_actor(:user)
    end

    update :update do
      accept @accepted

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
    validate {Electricbrain.Validations.OwnedParent,
              parent: Electricbrain.Metrics.Metric, field: :weight_metric_id}

    validate compare(:goal_rate_kcal_per_day, greater_than_or_equal_to: 0)
    validate compare(:protein_g_per_kg, greater_than: 0)
    validate compare(:fat_pct, greater_than: 0, less_than: 100)
    validate compare(:max_shakes_per_day, greater_than_or_equal_to: 0)
  end

  attributes do
    uuid_primary_key :id

    # Body / TDEE inputs
    attribute :height_cm, :decimal do
      allow_nil? true
      public? true
    end

    attribute :birthdate, :date do
      allow_nil? true
      public? true
    end

    attribute :sex, :atom do
      allow_nil? true
      public? true
      constraints one_of: [:male, :female]
    end

    attribute :activity_level, :atom do
      allow_nil? false
      default :light
      public? true
      constraints one_of: [:sedentary, :light, :moderate, :active, :very_active]
    end

    attribute :goal, :atom do
      allow_nil? false
      default :maintain
      public? true
      constraints one_of: [:cut, :maintain, :bulk]
    end

    attribute :goal_rate_kcal_per_day, :integer do
      allow_nil? false
      default 400
      public? true
    end

    # Macro split: protein by bodyweight, fat as a percentage of kcal,
    # carbs are the remainder.
    attribute :protein_g_per_kg, :decimal do
      allow_nil? false
      default Decimal.new("2.0")
      public? true
    end

    attribute :fat_pct, :decimal do
      allow_nil? false
      default Decimal.new(25)
      public? true
    end

    # Manual overrides — nil means "use the computed value".
    attribute :override_kcal, :integer do
      allow_nil? true
      public? true
    end

    attribute :override_protein_g, :integer do
      allow_nil? true
      public? true
    end

    attribute :override_fat_g, :integer do
      allow_nil? true
      public? true
    end

    attribute :override_carbs_g, :integer do
      allow_nil? true
      public? true
    end

    # Eating / reminder times, user-local.
    attribute :breakfast_time, :time do
      allow_nil? false
      default ~T[07:00:00]
      public? true
    end

    attribute :shake_time, :time do
      allow_nil? false
      default ~T[10:00:00]
      public? true
    end

    attribute :lunch_time, :time do
      allow_nil? false
      default ~T[12:30:00]
      public? true
    end

    attribute :snack_time, :time do
      allow_nil? false
      default ~T[15:00:00]
      public? true
    end

    attribute :dinner_time, :time do
      allow_nil? false
      default ~T[18:30:00]
      public? true
    end

    attribute :shopping_reminder_time, :time do
      allow_nil? false
      default ~T[08:00:00]
      public? true
    end

    attribute :prep_reminder_time, :time do
      allow_nil? false
      default ~T[09:00:00]
      public? true
    end

    attribute :max_shakes_per_day, :integer do
      allow_nil? false
      default 2
      public? true
    end

    # Saturday "no plan yet" nudge idempotence (meal scheduler).
    attribute :last_nudged_on, :date do
      allow_nil? true
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Electricbrain.Accounts.User do
      allow_nil? false
    end

    belongs_to :weight_metric, Electricbrain.Metrics.Metric do
      allow_nil? true
      public? true
    end
  end

  identities do
    identity :one_per_user, [:user_id]
  end
end
