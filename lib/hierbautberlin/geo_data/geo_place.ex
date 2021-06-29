defmodule Hierbautberlin.GeoData.GeoPlace do
  use Ecto.Schema

  alias Geo.PostGIS.Geometry

  schema "geo_places" do
    field :external_id, :string
    field :name, :string
    field :city, :string
    field :district, :string
    field :type, :string
    field :geometry, Geometry
    field :geo_point, Geometry

    timestamps(type: :utc_datetime)
  end
end
