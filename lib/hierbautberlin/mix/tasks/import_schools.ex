defmodule Mix.Tasks.ImportSchools do
  use Mix.Task

  alias Hierbautberlin.Repo
  alias Hierbautberlin.GeoData.GeoPlace

  @shortdoc "Imports schools into the database"
  def run(_) do
    Ecto.Migrator.with_repo(Hierbautberlin.Repo, fn _repo ->
      IO.puts("Importing to database")

      File.stream!("data/berlin-schools.csv")
      |> CSV.decode!(separator: ?;, headers: true)
      |> Stream.map(fn row ->
        point = %Geo.Point{
          coordinates: {String.to_float(row["Longitude"]), String.to_float(row["Latitude"])},
          srid: 4326
        }

        Repo.insert(
          %GeoPlace{
            external_id: row["\uFEFFBSN"],
            name: row["Name"],
            city: row["City"],
            type: "School",
            geo_point: point
          },
          on_conflict: :replace_all,
          conflict_target: :external_id
        )
      end)
      |> Stream.run()
    end)
  end
end
