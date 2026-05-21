import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/electricbrain start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :electricbrain, ElectricbrainWeb.Endpoint, server: true
end

config :electricbrain, ElectricbrainWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :electricbrain, Electricbrain.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :electricbrain, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :electricbrain, ElectricbrainWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  config :electricbrain,
    token_signing_secret:
      System.get_env("TOKEN_SIGNING_SECRET") ||
        raise("Missing environment variable `TOKEN_SIGNING_SECRET`!")

  # Auth0-fronted SSO. All three env vars are required in prod — the
  # oauth2 :auth0 strategy is compiled in unconditionally, so any missing
  # config would surface as a runtime auth failure rather than a clearer
  # boot-time error.
  auth0_domain =
    System.get_env("AUTH0_DOMAIN") ||
      raise("Missing environment variable `AUTH0_DOMAIN`!")

  auth0_client_id =
    System.get_env("AUTH0_CLIENT_ID") ||
      raise("Missing environment variable `AUTH0_CLIENT_ID`!")

  auth0_client_secret =
    System.get_env("AUTH0_CLIENT_SECRET") ||
      raise("Missing environment variable `AUTH0_CLIENT_SECRET`!")

  config :electricbrain,
    auth0_base_url: auth0_domain,
    auth0_client_id: auth0_client_id,
    auth0_client_secret: auth0_client_secret,
    auth0_redirect_uri: "https://#{host}/auth"

  # Google Calendar (per-user OAuth for Calendar API access). Optional —
  # if unset, the Settings page will show a configuration error when the
  # user tries to connect.
  if google_client_id = System.get_env("GOOGLE_CLIENT_ID") do
    config :electricbrain,
      google_client_id: google_client_id,
      google_client_secret:
        System.get_env("GOOGLE_CLIENT_SECRET") ||
          raise("Missing environment variable `GOOGLE_CLIENT_SECRET`!")
  end

  # Web push (VAPID). Generate a keypair once with `mix generate.vapid.keys`
  # and set these env vars. The Settings UI's notification controls degrade
  # gracefully if VAPID_PUBLIC_KEY is missing.
  if vapid_public_key = System.get_env("VAPID_PUBLIC_KEY") do
    config :web_push_elixir,
      vapid_public_key: vapid_public_key,
      vapid_private_key:
        System.get_env("VAPID_PRIVATE_KEY") ||
          raise("Missing environment variable `VAPID_PRIVATE_KEY`!"),
      vapid_subject:
        System.get_env("VAPID_SUBJECT") ||
          "mailto:#{System.get_env("CONTACT_EMAIL", "admin@example.com")}"
  end

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :electricbrain, ElectricbrainWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :electricbrain, ElectricbrainWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :electricbrain, Electricbrain.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
