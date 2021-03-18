defmodule Hierbautberlin.Repo.Migrations.CreateGeoStore do
  use Ecto.Migration

  def change do
    create table(:sources) do
      add :name, :string
      add :url, :text
      add :copyright, :string

      timestamps(type: :timestamptz)
    end

    create table(:geo_items) do
      add :title, :string
      add :subtitle, :string
      add :description, :text
      add :url, :text
      add :state, :string
      add :date_start, :timestamptz
      add :date_end, :timestamptz
      add :source_id, references(:sources)

      add :geo_geometry, :geometry

      timestamps(type: :timestamptz)
    end

    execute("SELECT AddGeometryColumn('geo_items', 'geo_point', 3857, 'POINT', 2);")
    # execute("SELECT AddGeometryColumn('geo_items', 'geo_geometry', 3857, 'GEOMETRY', 2);")

    execute("CREATE INDEX geo_items_point_idx ON geo_items USING GIST (geo_point);")
    execute("CREATE INDEX geo_items_geometry_idx ON geo_items USING GIST (geo_geometry);")
  end
end
