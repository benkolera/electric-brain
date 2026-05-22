import Config
config :electricbrain, token_signing_secret: "AipXgxZip7mQmVkrTEaKaZk8MWlP+++J"
config :electricbrain, :notifications, enabled: false
config :electricbrain, :notes_image_store_adapter, Electricbrain.Notes.ImageStore.Memory

# Speed up the focus scheduler so duration_minutes:1 fires in ~10ms.
# Tests using the scheduler still pay this delay; budget accordingly.
config :electricbrain, :focus_minute_ms, 10
# Skip boot_sweep — the supervised Scheduler runs outside any test's
# Ecto sandbox so a query at boot would fail and bring the supervisor
# down via restart-intensity. Tests that need sweep behaviour can call
# the sweep manually after allowing the sandbox.
config :electricbrain, :focus_scheduler, sweep: false
config :bcrypt_elixir, log_rounds: 1
config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true

# A deterministic dummy VAPID pair so the library config has something to
# read; tests never actually deliver pushes.
config :web_push_elixir,
  vapid_public_key:
    "BMxPa5w1smIyaeqaCy3nqcZ3C0j0W_SoAGcASJXnoBzAUVfys570QVvCIdMns6L1hDx7A5y8l2ZOanhCc5xU4MM",
  vapid_private_key: "Y0aQxcmHGLyvXFpYtB_LSMbyjGpvSh8kIq3s_dGI_Xo",
  vapid_subject: "mailto:test@example.com"

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :electricbrain, Electricbrain.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "electricbrain_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :electricbrain, ElectricbrainWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "RSrxNmvA1hg+DEpcSvaCSYLCsv+ee3zapvJ8OREs1+frKHa/7j/cTrzKAjVeU8us",
  server: false

# In test we don't send emails
config :electricbrain, Electricbrain.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
