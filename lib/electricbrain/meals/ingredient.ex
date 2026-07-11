defmodule Electricbrain.Meals.Ingredient do
  @moduledoc """
  A food with per-100g macros. Two kinds share the table, discriminated
  by `user_id`:

    * `user_id == nil` — global rows seeded from the Australian Food
      Composition Database (AFCD, FSANZ). Readable by every signed-in
      user, never editable through the UI, upserted by `afcd_code` so
      re-seeding updates values in place.
    * `user_id` set — a user's own entry, typed in from a packet label
      (branded products the AFCD doesn't carry).

  Macros are stored per 100g so recipe math is a single scale factor
  (`quantity_g / 100`).
  """

  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Meals,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "ingredients"
    repo Electricbrain.Repo
  end

  actions do
    defaults [:read, :destroy]

    read :search do
      argument :q, :string, allow_nil?: false

      filter expr(contains(string_downcase(name), string_downcase(^arg(:q))))
    end

    create :create do
      accept [
        :name,
        :kcal_per_100g,
        :protein_g_per_100g,
        :fat_g_per_100g,
        :carbs_g_per_100g,
        :fibre_g_per_100g
      ]

      change relate_actor(:user)
      change set_attribute(:source, :custom)
    end

    # Seeder-only: bypasses policies via authorize?: false. Idempotent —
    # re-running the seed updates macro values without duplicating rows.
    create :seed_upsert do
      accept [
        :name,
        :source,
        :afcd_code,
        :kcal_per_100g,
        :protein_g_per_100g,
        :fat_g_per_100g,
        :carbs_g_per_100g,
        :fibre_g_per_100g
      ]

      upsert? true
      upsert_identity :afcd_code

      upsert_fields [
        :name,
        :source,
        :kcal_per_100g,
        :protein_g_per_100g,
        :fat_g_per_100g,
        :carbs_g_per_100g,
        :fibre_g_per_100g
      ]
    end

    update :update do
      accept [
        :name,
        :kcal_per_100g,
        :protein_g_per_100g,
        :fat_g_per_100g,
        :carbs_g_per_100g,
        :fibre_g_per_100g
      ]
    end
  end

  policies do
    policy action(:seed_upsert) do
      forbid_if always()
    end

    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type(:read) do
      authorize_if expr(is_nil(user_id))
      authorize_if relates_to_actor_via(:user)
    end

    policy action_type([:update, :destroy]) do
      authorize_if relates_to_actor_via(:user)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :source, :atom do
      allow_nil? false
      default :custom
      public? true
      constraints one_of: [:afcd, :custom]
    end

    attribute :afcd_code, :string do
      allow_nil? true
      public? true
    end

    attribute :kcal_per_100g, :decimal do
      allow_nil? false
      public? true
    end

    attribute :protein_g_per_100g, :decimal do
      allow_nil? false
      public? true
    end

    attribute :fat_g_per_100g, :decimal do
      allow_nil? false
      public? true
    end

    attribute :carbs_g_per_100g, :decimal do
      allow_nil? false
      public? true
    end

    attribute :fibre_g_per_100g, :decimal do
      allow_nil? false
      default Decimal.new(0)
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Electricbrain.Accounts.User do
      allow_nil? true
    end
  end

  identities do
    identity :afcd_code, [:afcd_code]
  end
end
