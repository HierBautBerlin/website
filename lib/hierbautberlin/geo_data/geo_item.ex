defmodule Hierbautberlin.GeoData.GeoItem do
  use Ecto.Schema
  import Ecto.Changeset

  schema "geo_items" do
    field :title, :string
    field :geo_point, Geo.PostGIS.Geometry
    field :geo_polygon, Geo.PostGIS.Geometry

    timestamps()
  end

  def changeset(geo_item, attrs) do
    geo_item
    |> cast(attrs, [:title, :subtitle, :description, :url])
    |> validate_required([:title])
  end
end
