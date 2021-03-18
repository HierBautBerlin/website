defmodule Hierbautberlin.GeoData.GeoItem do
  use Ecto.Schema
  import Ecto.Changeset

  schema "geo_items" do
    field :title, :string
    field :subtitle, :string
    field :description, :string
    field :url, :string
    field :string, :string
    field :date_start, :utc_datetime
    field :date_end, :utc_datetime
    # field :source_id,
    field :geo_point, Geo.PostGIS.Geometry
    field :geo_geometry, Geo.PostGIS.Geometry

    timestamps(type: :utc_datetime)
  end

  def changeset(geo_item, attrs) do
    geo_item
    |> cast(attrs, [:title, :subtitle, :description, :url, :geo_point, :geo_geometry])
    |> validate_required([:title])
  end
end
