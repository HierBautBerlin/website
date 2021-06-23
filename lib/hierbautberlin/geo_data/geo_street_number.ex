defmodule Hierbautberlin.GeoData.GeoStreetNumber do
  use Ecto.Schema

  alias Geo.PostGIS.Geometry
  alias Hierbautberlin.GeoData.GeoStreet

  schema "geo_street_numbers" do
    field :external_id, :string
    field :number, :string
    field :zip, :string
    field :geo_point, Geometry

    belongs_to :geo_street, GeoStreet

    timestamps(type: :utc_datetime)
  end
end
