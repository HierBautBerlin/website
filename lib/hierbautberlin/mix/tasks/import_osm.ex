defmodule Mix.Tasks.ImportOsm do
  use Mix.Task

  @shortdoc "Imports streets and street numbers from an OpenStreetMap extract"

  @moduledoc """
  Imports streets and street numbers from an OpenStreetMap extract.

      mix import_osm [data/berlin-latest.osm.pbf]

  Needs `ogr2ogr` (gdal-bin). Existing ids and links to news items are kept.
  """

  def run(args) do
    file = List.first(args) || "data/berlin-latest.osm.pbf"

    Ecto.Migrator.with_repo(Hierbautberlin.Repo, fn _repo ->
      {time, stats} = :timer.tc(fn -> Hierbautberlin.GeoImport.import_osm(file) end)

      Mix.shell().info("""
      Import finished in #{div(time, 1_000_000)}s

      Staging:  #{inspect(stats.staging)}
      Before:   #{inspect(stats.before)}
      After:    #{inspect(stats.after)}
      Changes:  #{inspect(stats.changes)}
      """)
    end)
  end
end
