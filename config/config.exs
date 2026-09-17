# General application configuration
import Config

config :hierbautberlin,
  ecto_repos: [Hierbautberlin.Repo]

config :hierbautberlin, Hierbautberlin.Repo, types: Hierbautberlin.PostgresTypes

# Configures the endpoint
config :hierbautberlin, HierbautberlinWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  secret_key_base: "u8Ixm7iwdet1nKcY8Y4OJ99ojScoem+hizeEQWtFIb0zX22njaT8regTdd33sUJC",
  render_errors: [
    formats: [html: HierbautberlinWeb.ErrorHTML, json: HierbautberlinWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Hierbautberlin.PubSub,
  live_view: [signing_salt: "ocVH8z5c"]

config :hierbautberlin, :generators,
  binary_id: false,
  sample_binary_id: "11111111-1111-1111-1111-111111111111"

config :hierbautberlin, :import_path, "./import"
config :hierbautberlin, :file_storage_path, "./file_storage"

config :hierbautberlin, HierbautberlinWeb.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  app: [
    args:
      ~w(js/app.ts --bundle --target=es2022 --outdir=../priv/static/js --entry-names=app.bundle),
    cd: Path.expand("../assets", __DIR__)
  ],
  pdf_viewer: [
    args:
      ~w(js/pdfViewer.ts --bundle --target=es2022 --format=esm --outdir=../priv/static/js --entry-names=pdf.viewer.bundle),
    cd: Path.expand("../assets", __DIR__)
  ],
  map_worker: [
    args:
      ~w(node_modules/maplibre-gl/dist/maplibre-gl-worker.mjs --bundle --target=es2022 --format=esm --outdir=../priv/static/js --entry-names=maplibre-gl-worker.bundle),
    cd: Path.expand("../assets", __DIR__)
  ],
  pdf_worker: [
    args:
      ~w(node_modules/pdfjs-dist/legacy/build/pdf.worker.mjs --bundle --target=es2022 --format=esm --outdir=../priv/static/js --entry-names=pdf.worker.bundle),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configure dart_sass (the version is required)
config :dart_sass,
  version: "1.97.3",
  default: [
    args:
      ~w(--load-path=node_modules --silence-deprecation=import css/app.scss ../priv/static/css/app.css),
    cd: Path.expand("../assets", __DIR__)
  ],
  # only for the PDF viewer page, not part of app.css
  pdf_viewer: [
    args:
      ~w(--load-path=node_modules --silence-deprecation=import css/pdf_viewer.scss ../priv/static/css/pdf_viewer.css),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :bugsnag,
  release_stage: "development",
  use_logger: false,
  http_client: Hierbautberlin.BugsnagHTTPClient,
  exception_filter: Hierbautberlin.ExceptionFilter

config :gettext, :default_locale, "de"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
