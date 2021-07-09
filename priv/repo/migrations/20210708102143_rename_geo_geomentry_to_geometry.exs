defmodule Hierbautberlin.Repo.Migrations.RenameGeoGeomentryToGeometry do
  use Ecto.Migration

  def change do
    rename table("geo_items"), :geo_geometry, to: :geometry
  end
end
