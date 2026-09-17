defmodule Hierbautberlin.MixProject do
  use Mix.Project

  def project do
    [
      app: :hierbautberlin,
      version: "1.0.0+#{get_commit_sha()}",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader],
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

  # Docker builds have no .git directory, they pass the commit as SOURCE_COMMIT
  defp get_commit_sha do
    case System.get_env("SOURCE_COMMIT") do
      sha when sha not in [nil, ""] ->
        sha

      _ ->
        case System.cmd("git", ~w[rev-parse HEAD], stderr_to_stdout: true) do
          {sha, 0} -> String.trim(sha)
          _ -> "unknown"
        end
    end
  rescue
    # git is not installed
    ErlangError -> "unknown"
  end

  defp dialyzer do
    [
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      # test/support uses ExUnit, CI runs dialyzer with MIX_ENV=test
      plt_add_apps: [:mix, :ex_unit]
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
      {:bandit, "~> 1.5"},
      {:bcrypt_elixir, "~> 3.0"},
      {:bugsnag, "~> 3.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:csv, "~> 3.2"},
      {:dart_sass, "~> 0.7", runtime: Mix.env() == :dev},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ecto_psql_extras, "~> 0.8"},
      {:ecto_sql, "~> 3.12"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false},
      {:ex_machina, "~> 2.8", only: :test},
      {:fast_rss, "~> 0.5"},
      {:floki, "~> 0.38"},
      {:geo_postgis, "~> 3.7"},
      {:geo_turf, "~> 0.6"},
      {:gettext, "~> 0.26"},
      # tzdata (via timex) depends on hackney, force the patched 4.x line
      {:hackney, "~> 4.7"},
      {:html_entities, "~> 0.5.2"},
      {:jason, "~> 1.4"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:mix_test_watch, "~> 1.2", only: [:dev], runtime: false},
      {:phoenix, "~> 1.8.1"},
      {:phoenix_ecto, "~> 4.6"},
      {:phoenix_html, "~> 4.2"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:phoenix_live_reload, "~> 1.6", only: :dev},
      {:phoenix_live_view, "~> 1.1"},
      {:postgrex, ">= 0.19.0"},
      {:premailex, "~> 1.0"},
      {:req, "~> 0.5"},
      {:sweet_xml, "~> 0.7"},
      {:swoosh, "~> 1.19"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:timex, "~> 3.7"}
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
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": [
        "esbuild.install --if-missing",
        "sass.install --if-missing",
        "cmd npm install --prefix assets"
      ],
      # decoders (JBIG2, JPEG 2000) and fonts PDF.js loads when a PDF needs them
      "assets.pdfjs": &copy_pdfjs_files/1,
      "assets.build": [
        "esbuild app",
        "esbuild map_worker",
        "esbuild pdf_viewer",
        "esbuild pdf_worker",
        "assets.pdfjs",
        "sass default",
        "sass pdf_viewer"
      ],
      "assets.deploy": [
        "esbuild app --minify",
        "esbuild map_worker --minify",
        "esbuild pdf_viewer --minify",
        "esbuild pdf_worker --minify",
        "assets.pdfjs",
        "sass default --no-source-map --style=compressed",
        "sass pdf_viewer --no-source-map --style=compressed",
        "phx.digest"
      ]
    ]
  end

  # The files PDF.js loads at runtime (assets/js/pdfViewer.ts)
  defp copy_pdfjs_files(_args) do
    File.rm_rf!("priv/static/pdfjs")
    File.mkdir_p!("priv/static/pdfjs")

    for dir <- ~w(wasm standard_fonts) do
      File.cp_r!(
        Path.join("assets/node_modules/pdfjs-dist", dir),
        Path.join("priv/static/pdfjs", dir)
      )
    end
  end
end
