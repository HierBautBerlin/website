defmodule Hierbautberlin.Repo.Migrations.CreateGeoStore do
  use Ecto.Migration

  def change do
    create table(:sources) do
      add :short_name, :string
      add :name, :string
      add :url, :text
      add :copyright, :string

      timestamps(type: :timestamptz)
    end

    create unique_index(:sources, [:short_name])

    create table(:geo_items) do
      add :external_id, :string
      add :title, :string
      add :subtitle, :string
      add :description, :text
      add :url, :text
      add :state, :string
      add :date_start, :timestamptz
      add :date_end, :timestamptz
      add :source_id, references(:sources, on_delete: :delete_all)

      add :geo_geometry, :geometry

      timestamps(type: :timestamptz)
    end

    create unique_index(:geo_items, [:source_id, :external_id])

    execute("SELECT AddGeometryColumn('geo_items', 'geo_point', 3857, 'POINT', 2);")

    execute("CREATE INDEX geo_items_point_idx ON geo_items USING GIST (geo_point);")
    execute("CREATE INDEX geo_items_geometry_idx ON geo_items USING GIST (geo_geometry);")
  end
end
