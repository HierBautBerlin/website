defmodule Mix.Tasks.ImportPlaces do
  use Mix.Task

  @shortdoc "Imports LOR planning areas and schools from gdi.berlin.de"

  @moduledoc """
  Imports places from the WFS services of gdi.berlin.de.

      mix import_places [LOR] [School]

  Without arguments all types are imported. Parks are imported from
  OpenStreetMap with `mix import_osm`.
  """

  def run(args) do
    types = Hierbautberlin.GeoImport.Places.types()
    unknown = args -- types

    if unknown != [] do
      Mix.raise(
        "Unknown place types: #{Enum.join(unknown, ", ")}. Known types: #{Enum.join(types, ", ")}"
      )
    end

    types = if args == [], do: types, else: args

    Ecto.Migrator.with_repo(Hierbautberlin.Repo, fn _repo ->
      Application.ensure_all_started(:req)
      stats = Hierbautberlin.GeoImport.import_places(types)
      Mix.shell().info("Imported places: #{inspect(stats)}")
    end)
  end
end
