defmodule Electricbrain.Meals.ShoppingListItem do
  @moduledoc """
  One aggregated ingredient line on a confirmed week's shopping list:
  total grams across every planned meal (quantity × planned servings ÷
  recipe batch servings). Persisted — not derived — because the
  checked-off state has to survive reloads and plan edits mid-shop.

  Rebuilds upsert on `[meal_week_id, ingredient_id]`, updating the
  quantity while PRESERVING `checked_at`; ingredients no longer in the
  plan get their rows deleted.
  """

  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Meals,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "shopping_list_items"
    repo Electricbrain.Repo

    references do
      reference :meal_week, on_delete: :delete
      reference :ingredient, on_delete: :restrict
    end
  end

  actions do
    defaults [:read, :destroy]

    create :upsert do
      accept [:meal_week_id, :ingredient_id, :total_quantity_g]

      upsert? true
      upsert_identity :one_per_ingredient
      upsert_fields [:total_quantity_g]

      change relate_actor(:user)
    end

    update :toggle_checked do
      accept []
      require_atomic? false

      change fn changeset, _context ->
        new_value = if changeset.data.checked_at, do: nil, else: DateTime.utc_now()
        Ash.Changeset.change_attribute(changeset, :checked_at, new_value)
      end
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
  end

  attributes do
    uuid_primary_key :id

    attribute :total_quantity_g, :decimal do
      allow_nil? false
      public? true
    end

    attribute :checked_at, :utc_datetime_usec do
      allow_nil? true
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :meal_week, Electricbrain.Meals.MealWeek do
      allow_nil? false
      public? true
    end

    belongs_to :ingredient, Electricbrain.Meals.Ingredient do
      allow_nil? false
      public? true
    end

    belongs_to :user, Electricbrain.Accounts.User do
      allow_nil? false
    end
  end

  identities do
    identity :one_per_ingredient, [:meal_week_id, :ingredient_id]
  end
end
