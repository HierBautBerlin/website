defmodule Hierbautberlin.MixProject do
  use Mix.Project

  def project do
    [
      app: :hierbautberlin,
      version: "1.0.0+#{get_commit_sha()}",
      elixir: "~> 1.7",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:phoenix, :gettext] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      dialyzer: dialyzer(),
      releases: [
        # the name of the release. We can add more configurations if we want
        hierbautberlin: [
          # we'll target only Linux
          include_executables_for: [:unix],
          # see https://hexdocs.pm/mix/Mix.Tasks.Release.html#module-options
          applications: [runtime_tools: :permanent],
          # assembles the release and builds a tarball of it
          steps: [:assemble, :tar]
        ]
      ]
    ]
  end

  defp get_commit_sha do
    {sha, 0} = System.cmd("git", ~w[rev-parse HEAD])
    String.trim(sha)
  end

  defp dialyzer do
    [
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Hierbautberlin.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:aho_corasick, "~> 0.0.1"},
      {:bamboo_phoenix, "~> 1.0.0"},
      {:bamboo, "~> 2.1.0"},
      {:bcrypt_elixir, "~> 2.0"},
      {:bugsnag, "~> 3.0.0"},
      {:credo, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:csv, "~> 2.4"},
      {:dialyxir, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:downstream, "~> 1.1.0"},
      {:ecto_psql_extras, "~> 0.2"},
      {:ecto_sql, "~> 3.4"},
      {:ex_check, "~> 0.14.0", only: [:dev, :test], runtime: false},
      {:ex_machina, "~> 2.7.0", only: :test},
      {:ex_unicode, "~> 1.11.2"},
      {:exkml, github: "bitboxer/exkml", branch: "update-deps"},
      {:fast_rss, "~> 0.3.4"},
      {:floki, ">= 0.27.0"},
      {:geo_postgis, "~> 3.1"},
      {:geo_turf, "~> 0.1.0"},
      {:gettext, "~> 0.11"},
      {:html_entities, "~> 0.5.2"},
      {:httpoison, "~> 1.8"},
      {:jason, "~> 1.0"},
      {:jaxon, "~> 2.0"},
      {:mix_test_watch, "~> 1.0", only: [:dev], runtime: false},
      {:phoenix_ecto, "~> 4.1"},
      {:phoenix_html_simplified_helpers, "~> 2.1.0"},
      {:phoenix_html, "~> 2.11"},
      {:phoenix_inline_svg, "~> 1.4"},
      {:phoenix_live_dashboard, "~> 0.4"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 0.15.1"},
      {:phoenix, "~> 1.5.8"},
      {:phx_gen_auth, "~> 0.7", only: [:dev], runtime: false},
      {:plug_cowboy, "~> 2.0"},
      {:postgrex, ">= 0.0.0"},
      {:premailex, "~> 0.3.13"},
      {:rustler, "~> 0.22.0", override: true},
      {:sweet_xml, "~> 0.7.0"},
      {:telemetry_metrics, "~> 0.4"},
      {:telemetry_poller, "~> 0.4"},
      {:timex, "~> 3.7.2"},
      {:jiffy_ex, "~> 1.1.0"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "cmd yarn install --cwd assets"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
