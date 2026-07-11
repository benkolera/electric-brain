defmodule Electricbrain.Meals.RecipeIngredient do
  @moduledoc """
  One ingredient line in a recipe: `quantity_g` grams of an ingredient.
  Quantities are grams-only so macro math is a single scale factor from
  the ingredient's per-100g values.

  `user_id` is denormalised from the recipe for simple ownership
  policies. The ingredient may be a global AFCD row or one of the
  user's own — `Validations.OwnedParent` against `Ingredient` enforces
  exactly that, since the ingredient read policy already encodes
  global-or-owned visibility.
  """

  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Meals,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "recipe_ingredients"
    repo Electricbrain.Repo

    references do
      reference :recipe, on_delete: :delete
      reference :ingredient, on_delete: :restrict
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:recipe_id, :ingredient_id, :quantity_g]

      change relate_actor(:user)
    end

    update :update do
      primary? true
      accept [:quantity_g]
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
              parent: Electricbrain.Meals.Recipe, field: :recipe_id}

    validate {Electricbrain.Validations.OwnedParent,
              parent: Electricbrain.Meals.Ingredient, field: :ingredient_id}

    validate compare(:quantity_g, greater_than: 0)
  end

  attributes do
    uuid_primary_key :id

    attribute :quantity_g, :decimal do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :recipe, Electricbrain.Meals.Recipe do
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
    identity :unique_per_recipe, [:recipe_id, :ingredient_id]
  end
end
