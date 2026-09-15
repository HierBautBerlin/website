defmodule Mix.Tasks.Importer.Check do
  use Mix.Task

  @shortdoc "Runs the importers against the live sources without storing data"

  @moduledoc """
  Runs the importers against the live data sources. Nothing is stored: every
  importer runs in a transaction that is rolled back. Response bodies are saved
  to `tmp/importer_check/<importer>/`.

      mix importer.check                     # all importers
      mix importer.check uvp berlin_presse   # only some
  """

  alias Hierbautberlin.Importer.Check

  def run(args) do
    names = if args == [], do: Check.importer_names(), else: args

    # Start the repo and the text analysis, but no web server or cron jobs
    Application.put_env(:hierbautberlin, :data_importer, true)

    Application.put_env(
      :hierbautberlin,
      :file_storage_path,
      Path.join(System.tmp_dir!(), "importer_check_storage")
    )

    Mix.Task.run("app.start")

    for report <- Check.run(names) do
      Mix.shell().info("\n== #{report.name} (#{report.duration_s}s)")

      for request <- report.requests do
        Mix.shell().info(
          "   #{request.status} #{request.bytes}B #{request.ms}ms #{request.url |> String.slice(0, 110)}"
        )
      end

      Mix.shell().info("   result: #{inspect(report.result, printable_limit: 300, limit: 20)}")
    end
  end
end
