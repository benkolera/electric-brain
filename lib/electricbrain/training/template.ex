defmodule Electricbrain.Training.Template do
  @moduledoc """
  A session template ("A", "B") in rotation order. Sessions alternate
  through templates by `position`, wrapping — the classic A/B split,
  extensible to A/B/C by adding a row. Slots are ordered and either
  pin a specific exercise or mark an accessory rotation point (see
  `TemplateSlot`).
  """

  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Training,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "training_templates"
    repo Electricbrain.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :position]

      argument :slots, {:array, :map} do
        allow_nil? true
        default []
      end

      change relate_actor(:user)

      change manage_relationship(:slots, type: :direct_control)
    end

    update :update do
      accept [:name, :position]

      argument :slots, {:array, :map} do
        allow_nil? true
      end

      require_atomic? false

      change manage_relationship(:slots, type: :direct_control)
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

    attribute :position, :integer do
      allow_nil? false
      default 0
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Electricbrain.Accounts.User do
      allow_nil? false
    end

    has_many :slots, Electricbrain.Training.TemplateSlot do
      sort position: :asc
    end
  end

  identities do
    identity :unique_name_per_user, [:user_id, :name]
  end
end
