defmodule Electricbrain.Devices.Pairing do
  @moduledoc """
  A long-lived bearer token issued to one external client (e.g. one
  install of the Trellis Even Hub plugin on one phone). The cleartext
  token is shown to the client exactly once during pairing; we persist
  only its SHA-256 hash.

  Lifecycle:
    * created by `Electricbrain.Devices.redeem_code/2` after the client
      submits a valid pairing code,
    * `:touch`-ed on each authenticated API request,
    * destroyed when the user unpairs from Settings or when the client
      revokes itself.
  """

  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Devices,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "device_pairings"
    repo Electricbrain.Repo
  end

  actions do
    defaults [:read, :destroy]

    # Server-only — the controller path uses `authorize?: false` because
    # the actor isn't established yet (the token is the credential being
    # minted). User-facing destroy is gated by the policy below.
    create :issue do
      accept [:token_hash, :label, :user_id]
    end

    update :touch do
      accept []
      change set_attribute(:last_seen_at, &DateTime.utc_now/0)
    end
  end

  policies do
    policy action_type([:read, :update, :destroy]) do
      authorize_if relates_to_actor_via(:user)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :token_hash, :string do
      allow_nil? false
      sensitive? true
    end

    attribute :label, :string do
      allow_nil? false
      public? true
    end

    attribute :last_seen_at, :utc_datetime_usec do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Electricbrain.Accounts.User do
      allow_nil? false
    end
  end

  identities do
    identity :unique_token_hash, [:token_hash]
  end
end
