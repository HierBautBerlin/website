defmodule Hierbautberlin.GeoData.GeoStreet do
  use Ecto.Schema

  alias Geo.PostGIS.Geometry
  alias Hierbautberlin.GeoData.{GeoStreetNumber, NewsItem}

  schema "geo_streets" do
    field :name, :string
    field :city, :string
    field :district, :string
    field :geometry, Geometry
    field :geo_point, Geometry

    has_many :street_numbers, GeoStreetNumber

    many_to_many :news_items, NewsItem,
      join_through: "geo_streets_news_items",
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end
end
