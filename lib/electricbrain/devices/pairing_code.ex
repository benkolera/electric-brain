defmodule Electricbrain.Devices.PairingCode do
  @moduledoc """
  Short-lived (10 minute TTL) code the user reads off the Settings page
  and types into an unauthenticated external client. Consumed by
  `Electricbrain.Devices.redeem_code/2` in exchange for a long-lived
  bearer token. The code itself is uniformly random over an unambiguous
  alphabet (no 0/O/1/I/L); collisions are vanishingly rare given the TTL,
  but a unique index makes it explicit.
  """

  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Devices,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "device_pairing_codes"
    repo Electricbrain.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :generate do
      accept [:code, :expires_at]
      change relate_actor(:user)
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type([:read, :destroy]) do
      authorize_if relates_to_actor_via(:user)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :code, :string do
      allow_nil? false
      public? true
    end

    attribute :expires_at, :utc_datetime_usec do
      allow_nil? false
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
    identity :unique_code, [:code]
  end
end
