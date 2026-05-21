defmodule Electricbrain.Moments.Moment do
  @moduledoc """
  A "radical acceptance" pause — sitting with a craving, urge, or strong
  feeling, naming it, and journaling through Tara Brach's RAIN steps so it
  loses its grip on the present.

    * Recognize — what's here right now?
    * Allow     — can I let it be?
    * Investigate — what does it want / where do I feel it in my body?
    * Nurture   — what does this part of me need?

  All four RAIN fields are optional — the bare minimum is `kind`, `name`,
  `intensity`. Filling in all four is the structured practice; filling in
  none is still a valid acknowledgement that the moment happened.
  """

  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Moments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "moments"
    repo Electricbrain.Repo

    references do
      reference :category, on_delete: :restrict
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :kind,
        :name,
        :intensity,
        :recognize,
        :allow,
        :investigate,
        :nurture,
        :category_id
      ]

      change relate_actor(:user)
    end

    update :update do
      accept [
        :kind,
        :name,
        :intensity,
        :recognize,
        :allow,
        :investigate,
        :nurture,
        :category_id
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

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:craving, :urge, :feeling, :other]
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :intensity, :integer do
      allow_nil? false
      public? true
      default 3
      constraints min: 1, max: 5
    end

    attribute :recognize, :string do
      allow_nil? true
      public? true
    end

    attribute :allow, :string do
      allow_nil? true
      public? true
    end

    attribute :investigate, :string do
      allow_nil? true
      public? true
    end

    attribute :nurture, :string do
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
  end
end
