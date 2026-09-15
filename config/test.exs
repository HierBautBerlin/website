import Config

config :hierbautberlin, :environment, :test

# Never the ./file_storage of development, which may contain a copy of production
config :hierbautberlin, :file_storage_path, "./tmp/test/file_storage"
config :hierbautberlin, :import_path, "./tmp/test/import"

# requests to plausible.io are answered by Req.Test stubs
config :hierbautberlin, :plausible_req_options,
  plug: {Req.Test, HierbautberlinWeb.Plugs.PlausibleProxy}

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :hierbautberlin, Hierbautberlin.Repo,
  username: "postgres",
  password: "postgres",
  database: "hierbautberlin_test#{System.get_env("MIX_TEST_PARTITION")}",
  hostname: System.get_env("DATABASE_HOST", "localhost"),
  port: String.to_integer(System.get_env("DATABASE_PORT", "5432")),
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :hierbautberlin, HierbautberlinWeb.Endpoint,
  http: [port: 4002],
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

config :hierbautberlin, HierbautberlinWeb.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
