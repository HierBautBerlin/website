defmodule Hierbautberlin.GeoData.GeoStreetNumber do
  use Ecto.Schema

  alias Geo.PostGIS.Geometry
  alias Hierbautberlin.GeoData.{GeoStreet, NewsItem}

  schema "geo_street_numbers" do
    field :external_id, :string
    field :number, :string
    field :zip, :string
    field :geo_point, Geometry

    belongs_to :geo_street, GeoStreet

    many_to_many :news_items, NewsItem,
      join_through: "geo_street_numbers_news_items",
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end
end
