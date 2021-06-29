defmodule Hierbautberlin.Repo.Migrations.AddGeoPlaces do
  use Ecto.Migration

  def change do
    create table(:geo_places) do
      add :external_id, :string
      add :name, :string
      add :district, :string
      add :city, :string
      add :type, :string
      timestamps(type: :timestamptz)
    end

    create unique_index(:geo_places, [:external_id])

    execute(
      "SELECT AddGeometryColumn('geo_places', 'geometry', 4326, 'GEOMETRY', 2);",
      "SELECT DropGeometryColumn('geo_places', 'geometry')"
    )

    execute(
      "SELECT AddGeometryColumn('geo_places', 'geo_point', 4326, 'POINT', 2);",
      "SELECT DropGeometryColumn('geo_places', 'geo_point');"
    )
  end
end
