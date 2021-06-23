defmodule Hierbautberlin.GeoData.GeoStreet do
  use Ecto.Schema

  alias Geo.PostGIS.Geometry
  alias Hierbautberlin.GeoData.GeoStreetNumber

  schema "geo_streets" do
    field :name, :string
    field :city, :string
    field :district, :string
    field :geometry, Geometry
    field :geo_point, Geometry

    has_many :street_numbers, GeoStreetNumber

    timestamps(type: :utc_datetime)
  end
end
