defmodule Electricbrain.Categories.Category do
  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Categories,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "categories"
    repo Electricbrain.Repo

    references do
      reference :parent, on_delete: :restrict
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :parent_id, :kind]
      change relate_actor(:user)
    end

    update :update do
      accept [:name, :color_id]
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

    attribute :kind, :atom do
      allow_nil? false
      default :standard
      public? true
      constraints one_of: [:standard, :inbox]
    end

    # Google Calendar's fixed 11-color palette (see
    # Electricbrain.Categories.Colors for the id↔hex map). Nil means
    # "inherit from parent"; root with nil falls back to the default.
    attribute :color_id, :integer do
      allow_nil? true
      public? true
      constraints min: 1, max: 11
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Electricbrain.Accounts.User do
      allow_nil? false
    end

    belongs_to :parent, __MODULE__ do
      allow_nil? true
      public? true
    end

    has_many :children, __MODULE__ do
      destination_attribute :parent_id
    end
  end
end
