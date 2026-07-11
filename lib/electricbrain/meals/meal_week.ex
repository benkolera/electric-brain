defmodule Electricbrain.Meals.MealWeek do
  @moduledoc """
  One generated week of meals (Mon–Fri), keyed by the user-local
  Monday. Targets are SNAPSHOTTED at generation time so later profile
  edits don't shift an already-planned week; `warnings` carries the
  generator's shortfall flags for the review banner.

  Lifecycle: `:draft` (regeneratable, editable) → `:confirmed`
  (locked in; shopping list builds, reminders arm).
  `shopping_notified_at` / `prep_notified_at` are the Saturday and
  Sunday reminder idempotence marks, mirroring `Planner.Entry.notified_at`.
  """

  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Meals,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "meal_weeks"
    repo Electricbrain.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :week_start,
        :target_kcal,
        :target_protein_g,
        :target_fat_g,
        :target_carbs_g,
        :warnings
      ]

      change relate_actor(:user)
    end

    update :confirm do
      accept []
      change set_attribute(:status, :confirmed)
    end

    update :mark_shopping_notified do
      accept []
      require_atomic? false
      change set_attribute(:shopping_notified_at, &DateTime.utc_now/0)
    end

    update :mark_prep_notified do
      accept []
      require_atomic? false
      change set_attribute(:prep_notified_at, &DateTime.utc_now/0)
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

    attribute :week_start, :date do
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :draft
      public? true
      constraints one_of: [:draft, :confirmed]
    end

    attribute :target_kcal, :integer do
      allow_nil? false
      public? true
    end

    attribute :target_protein_g, :integer do
      allow_nil? false
      public? true
    end

    attribute :target_fat_g, :integer do
      allow_nil? false
      public? true
    end

    attribute :target_carbs_g, :integer do
      allow_nil? false
      public? true
    end

    attribute :warnings, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :shopping_notified_at, :utc_datetime_usec do
      allow_nil? true
    end

    attribute :prep_notified_at, :utc_datetime_usec do
      allow_nil? true
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Electricbrain.Accounts.User do
      allow_nil? false
    end

    has_many :planned_meals, Electricbrain.Meals.PlannedMeal
  end

  identities do
    identity :one_per_week, [:user_id, :week_start]
  end
end
