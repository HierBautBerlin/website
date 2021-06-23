defmodule Hierbautberlin.Repo.Migrations.AddGeoStreets do
  use Ecto.Migration

  def change do
    create table(:geo_streets) do
      add :name, :string
      add :district, :string
      add :city, :string
      timestamps(type: :timestamptz)
    end

    execute("SELECT AddGeometryColumn('geo_streets', 'geometry', 4326, 'GEOMETRY', 2);")
    execute("SELECT AddGeometryColumn('geo_streets', 'geo_point', 4326, 'POINT', 2);")

    create table(:geo_street_numbers) do
      add :external_id, :string
      add :geo_street_id, references(:geo_streets, on_delete: :delete_all), null: false
      add :number, :string
      add :zip, :string

      timestamps(type: :timestamptz)
    end

    create index(:geo_street_numbers, [:external_id])

    execute("SELECT AddGeometryColumn('geo_street_numbers', 'geo_point', 4326, 'POINT', 2);")
  end
end
