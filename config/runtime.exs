import Config

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  config :hierbautberlin, Hierbautberlin.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  config :hierbautberlin, :import_path, System.get_env("HIERBAUT_IMPORT_PATH")
  config :hierbautberlin, :file_storage_path, System.get_env("HIERBAUT_STORAGE_PATH")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  config :bugsnag,
    release_stage: "production",
    use_logger: true,
    api_key: System.get_env("BUGSNAG_API")

  config :hierbautberlin, HierbautberlinWeb.Endpoint,
    http: [
      port: String.to_integer(System.get_env("PORT") || "4000"),
      transport_options: [socket_opts: [:inet6]]
    ],
    secret_key_base: secret_key_base

  config :hierbautberlin, HierbautberlinWeb.Mailer,
    adapter: Bamboo.MailgunAdapter,
    api_key: System.get_env("MAILGUN_API"),
    domain: System.get_env("MAILGUN_DOMAIN"),
    base_uri: "https://api.eu.mailgun.net/v3"
end
