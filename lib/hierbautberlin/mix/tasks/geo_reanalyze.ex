defmodule Mix.Tasks.Geo.Reanalyze do
  use Mix.Task

  @shortdoc "Runs the address matching again for existing news items"

  @moduledoc """
  Runs the address matching again for existing news items.

      mix geo.reanalyze BERLIN_AMTSBLATT [--since 2026-01-01] [--stored-only] [--apply]
      mix geo.reanalyze BERLIN_PRESSE --since 2026-09-01 --apply

  Without `--apply` nothing is changed, only the statistics are printed. With
  `--stored-only` only the stored texts are used, nothing is fetched or extracted.
  In production use `Hierbautberlin.GeoData.Reanalyze.run/1` via `bin/hierbautberlin eval`.
  """

  alias Hierbautberlin.GeoData.{AnalyzeText, MapFeatures, Reanalyze}

  def run(args) do
    {opts, [source], _} =
      OptionParser.parse(args,
        strict: [since: :string, apply: :boolean, stored_only: :boolean]
      )

    since =
      case opts[:since] do
        nil -> nil
        date -> DateTime.new!(Date.from_iso8601!(date), ~T[00:00:00], "Etc/UTC")
      end

    Application.put_env(:hierbautberlin, :data_importer, true)
    Mix.Task.run("app.start")
    AnalyzeText.reload()

    stats =
      Reanalyze.run(
        source: source,
        since: since,
        dry_run: !opts[:apply],
        stored_only: opts[:stored_only] || false
      )

    Mix.shell().info(inspect(stats))

    if opts[:apply], do: MapFeatures.refresh()
  end
end
