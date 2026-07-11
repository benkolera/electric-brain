defmodule Electricbrain.Meals.Recipe do
  @moduledoc """
  A user's dish built from ingredients with gram quantities. `servings`
  is how many servings the ingredient list makes — per-serving macros
  are computed (never stored) by `Electricbrain.Meals.Macros` from the
  loaded `recipe_ingredients`.

  `slot_type` drives where the weekly plan generator may place the
  recipe: `:breakfast`, `:main` (lunch/dinner), `:snack`, or `:shake`
  (protein top-ups).
  """

  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Meals,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "recipes"
    repo Electricbrain.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :slot_type, :servings, :instructions]

      argument :recipe_ingredients, {:array, :map} do
        allow_nil? true
        default []
      end

      change relate_actor(:user)

      change manage_relationship(:recipe_ingredients,
               type: :direct_control,
               use_identities: [:unique_per_recipe]
             )
    end

    update :update do
      accept [:name, :slot_type, :servings, :instructions]

      argument :recipe_ingredients, {:array, :map} do
        allow_nil? true
      end

      require_atomic? false

      change manage_relationship(:recipe_ingredients,
               type: :direct_control,
               use_identities: [:unique_per_recipe]
             )
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
    validate compare(:servings, greater_than: 0)
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :slot_type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:breakfast, :main, :snack, :shake]
    end

    attribute :servings, :decimal do
      allow_nil? false
      default Decimal.new(1)
      public? true
    end

    attribute :instructions, :string do
      allow_nil? true
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Electricbrain.Accounts.User do
      allow_nil? false
    end

    has_many :recipe_ingredients, Electricbrain.Meals.RecipeIngredient
  end
end
