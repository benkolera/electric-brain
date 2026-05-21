defmodule Electricbrain.Notifications.PushSubscription do
  @moduledoc """
  A single browser subscription to web push notifications. A user can have
  multiple — one per device/browser. Created when the user clicks "Enable
  notifications" in Settings; deleted when they disable or when the push
  service reports the subscription as expired/gone.
  """

  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Notifications,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "push_subscriptions"
    repo Electricbrain.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:endpoint, :p256dh_key, :auth_key, :user_agent]
      change relate_actor(:user)
    end

    update :touch do
      accept []
      change set_attribute(:last_used_at, &DateTime.utc_now/0)
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

    attribute :endpoint, :string do
      allow_nil? false
      public? true
    end

    attribute :p256dh_key, :string do
      allow_nil? false
      public? true
    end

    attribute :auth_key, :string do
      allow_nil? false
      public? true
    end

    attribute :user_agent, :string do
      allow_nil? true
      public? true
    end

    attribute :last_used_at, :utc_datetime_usec do
      allow_nil? true
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
    identity :unique_endpoint_per_user, [:user_id, :endpoint]
  end
end
