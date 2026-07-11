defmodule Electricbrain.Meals.PlannedMeal do
  @moduledoc """
  One cell of the weekly meal grid: a recipe at (date, slot) with a
  scaled `servings` multiplier. Multiple shakes on a day are expressed
  as higher servings on the single `:shake` row, keeping the week a
  strict 5×5 matrix.

  `notified_at` is the meal-time reminder idempotence mark (the meals
  scheduler mirrors `Planner.Entry.notified_at`). `recipe_id` is
  on_delete: :restrict — recipes referenced by any planned week can't
  be deleted.
  """

  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Meals,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "planned_meals"
    repo Electricbrain.Repo

    references do
      reference :meal_week, on_delete: :delete
      reference :recipe, on_delete: :restrict
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:meal_week_id, :recipe_id, :date, :slot, :servings]

      change relate_actor(:user)
    end

    update :swap do
      accept [:recipe_id, :servings]
      require_atomic? false
    end

    update :mark_notified do
      accept []
      require_atomic? false
      change set_attribute(:notified_at, &DateTime.utc_now/0)
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
              parent: Electricbrain.Meals.MealWeek, field: :meal_week_id}

    validate {Electricbrain.Validations.OwnedParent,
              parent: Electricbrain.Meals.Recipe, field: :recipe_id}

    validate compare(:servings, greater_than: 0)
  end

  attributes do
    uuid_primary_key :id

    attribute :date, :date do
      allow_nil? false
      public? true
    end

    attribute :slot, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:breakfast, :shake, :lunch, :snack, :dinner]
    end

    attribute :servings, :decimal do
      allow_nil? false
      public? true
    end

    attribute :notified_at, :utc_datetime_usec do
      allow_nil? true
    end

    timestamps()
  end

  relationships do
    belongs_to :meal_week, Electricbrain.Meals.MealWeek do
      allow_nil? false
      public? true
    end

    belongs_to :recipe, Electricbrain.Meals.Recipe do
      allow_nil? false
      public? true
    end

    belongs_to :user, Electricbrain.Accounts.User do
      allow_nil? false
    end
  end

  identities do
    identity :one_per_slot, [:meal_week_id, :date, :slot]
  end
end
