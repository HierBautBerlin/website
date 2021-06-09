# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :hierbautberlin,
  ecto_repos: [Hierbautberlin.Repo]

config :hierbautberlin, Hierbautberlin.Repo, types: Hierbautberlin.PostgresTypes

# Configures the endpoint
config :hierbautberlin, HierbautberlinWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "u8Ixm7iwdet1nKcY8Y4OJ99ojScoem+hizeEQWtFIb0zX22njaT8regTdd33sUJC",
  render_errors: [view: HierbautberlinWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Hierbautberlin.PubSub,
  live_view: [signing_salt: "ocVH8z5c"]

config :hierbautberlin, :generators,
  binary_id: false,
  sample_binary_id: "11111111-1111-1111-1111-111111111111"

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :bugsnag,
  release_stage: "development",
  use_logger: false,
  exception_filter: Hierbautberlin.ExceptionFilter

config :gettext, :default_locale, "de"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
