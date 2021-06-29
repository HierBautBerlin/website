defmodule Mix.Tasks.ImportParks do
  use Mix.Task

  alias Hierbautberlin.Repo
  alias Hierbautberlin.GeoData.GeoPlace

  @shortdoc "Imports parks data into the database"
  def run(_) do
    Ecto.Migrator.with_repo(Hierbautberlin.Repo, fn _repo ->
      IO.puts("Importing to database")

      "data/berlin-parks.geojson"
      |> File.stream!()
      |> Jaxon.Stream.from_enumerable()
      |> Jaxon.Stream.query([:root, "features", :all])
      |> Stream.each(fn item ->
        IO.puts(item["properties"]["namenr"])

        geometry = Map.merge(Geo.JSON.decode!(item), %{srid: 4326})
        center = Map.merge(Geo.Turf.Measure.center(geometry), %{srid: 4326})

        Repo.insert(
          %GeoPlace{
            external_id: item["properties"]["gml_id"],
            name: item["properties"]["namenr"],
            city: "Berlin",
            district: item["properties"]["bezirkname"],
            type: "Park",
            geometry: geometry,
            geo_point: center
          },
          on_conflict: :replace_all,
          conflict_target: :external_id
        )
      end)
      |> Stream.run()
    end)
  end
end
