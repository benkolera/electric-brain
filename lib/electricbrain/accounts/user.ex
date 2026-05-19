defmodule Electricbrain.Accounts.User do
  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication]

  authentication do
    add_ons do
      log_out_everywhere do
        apply_on_password_change? true
      end
    end

    tokens do
      enabled? true
      token_resource Electricbrain.Accounts.Token
      signing_secret Electricbrain.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      # Password strategy is dev/test only. The prod release is built
      # with MIX_ENV=prod, so this branch is skipped at compile time and
      # there is no /sign-in form, no register_with_password action, no
      # way to set hashed_password from the running app. Prod auth is
      # Auth0 only.
      if Mix.env() in [:dev, :test] do
        password :password do
          identity_field :email
          hash_provider AshAuthentication.BcryptProvider
        end
      end

      # Auth0-fronted SSO. Registration is enabled so the very first
      # sign-in creates the user. The tenant's post-login allowlist
      # (configured externally) gates who can ever land here.
      oauth2 :auth0 do
        client_id Electricbrain.Secrets
        client_secret Electricbrain.Secrets
        base_url Electricbrain.Secrets
        redirect_uri Electricbrain.Secrets
        authorize_url fn _, _ -> {:ok, "/authorize"} end
        token_url fn _, _ -> {:ok, "/oauth/token"} end
        user_url fn _, _ -> {:ok, "/userinfo"} end
        authorization_params scope: "openid profile email"
        register_action_name :register_with_auth0
        prevent_hijacking? false
      end
    end
  end

  postgres do
    table "users"
    repo Electricbrain.Repo
  end

  actions do
    defaults [:read]

    read :get_by_subject do
      description "Get a user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    read :get_by_email do
      description "Looks up a user by their email"
      get? true
      argument :email, :ci_string, allow_nil?: false
      filter expr(email == ^arg(:email))
    end

    update :set_timezone do
      accept [:timezone]
    end

    update :connect_google do
      description "Stores Google OAuth tokens after a successful OAuth callback"

      accept [
        :google_email,
        :google_access_token,
        :google_refresh_token,
        :google_token_expires_at
      ]

      require_atomic? false
    end

    update :refresh_google_tokens do
      description "Updates access token and expiry after a refresh-token exchange"
      accept [:google_access_token, :google_token_expires_at]
      require_atomic? false
    end

    update :disconnect_google do
      description "Clears Google OAuth tokens"
      accept []
      require_atomic? false

      change set_attribute(:google_email, nil)
      change set_attribute(:google_access_token, nil)
      change set_attribute(:google_refresh_token, nil)
      change set_attribute(:google_token_expires_at, nil)
    end

    create :register_with_auth0 do
      description "Upsert-by-email registration triggered by an Auth0 OAuth callback"
      argument :user_info, :map, allow_nil?: false
      argument :oauth_tokens, :map, allow_nil?: false
      upsert? true
      upsert_identity :unique_email

      change AshAuthentication.GenerateTokenChange

      change fn changeset, _ctx ->
        user_info = Ash.Changeset.get_argument(changeset, :user_info)
        Ash.Changeset.change_attribute(changeset, :email, user_info["email"])
      end
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action(:set_timezone) do
      authorize_if expr(id == ^actor(:id))
    end

    policy action([:connect_google, :refresh_google_tokens, :disconnect_google]) do
      authorize_if expr(id == ^actor(:id))
    end
  end

  # Resource-level change so default categories get seeded for both auth flows
  # (register_with_password in dev/test and register_with_auth0 in prod). The
  # seeding is idempotent — if the user already has categories it's a no-op.
  changes do
    change after_action(fn _changeset, user, _context ->
             Electricbrain.Categories.seed_defaults_for(user)
             {:ok, user}
           end),
           on: [:create]
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    # Nullable so Auth0-only users (no local password) can exist.
    # The password strategy still validates presence at sign-in time.
    attribute :hashed_password, :string do
      allow_nil? true
      sensitive? true
    end

    attribute :confirmed_at, :utc_datetime_usec

    attribute :timezone, :string do
      allow_nil? false
      default "Etc/UTC"
      public? true
    end

    # Google Calendar integration. All four are populated on successful
    # OAuth connection. `refresh_token` is the long-lived credential; the
    # access token is rotated via the refresh endpoint.
    attribute :google_email, :string do
      public? true
    end

    attribute :google_access_token, :string do
      sensitive? true
    end

    attribute :google_refresh_token, :string do
      sensitive? true
    end

    attribute :google_token_expires_at, :utc_datetime_usec
  end

  identities do
    identity :unique_email, [:email]
  end
end
