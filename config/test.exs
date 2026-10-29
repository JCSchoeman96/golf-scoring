import Config

config :golf_scoring, GolfScoring.Repo,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :ash,
  policies: [show_policy_breakdowns?: true],
  keyset_signing_secret: "LYTtjQ8jMfeUbYIUrfstoDxKIFcasDX/+6JWe2eSuQs",
  disable_async?: true

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :golf_scoring, GolfScoringWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Op8ShwtVCKOVE+e3PR1r6/1Cs/mGOhMprB71iwUiSMhfuZbAoLPdPi1RWMkPqG/R",
  server: false

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
