defmodule Hierbautberlin.Repo.Migrations.AddGeometryToNewsItems do
  use Ecto.Migration

  def change do
    execute(
      "SELECT AddGeometryColumn('news_items', 'geometries', 4326, 'GEOMETRY', 2);",
      "SELECT DropGeometryColumn('news_items', 'geometries')"
    )

    execute(
      "SELECT AddGeometryColumn('news_items', 'geo_points', 4326, 'GEOMETRY', 2);",
      "SELECT DropGeometryColumn('news_items', 'geo_points')"
    )
  end
end
