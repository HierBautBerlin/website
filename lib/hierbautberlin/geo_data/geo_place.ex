defmodule Hierbautberlin.GeoData.GeoPlace do
  use Ecto.Schema

  alias Geo.PostGIS.Geometry

  alias Hierbautberlin.GeoData.NewsItem

  schema "geo_places" do
    field :external_id, :string
    field :name, :string
    field :city, :string
    field :district, :string
    field :type, :string
    field :geometry, Geometry
    field :geo_point, Geometry

    many_to_many :news_items, NewsItem, join_through: "geo_places_news_items"

    timestamps(type: :utc_datetime)
  end
end
