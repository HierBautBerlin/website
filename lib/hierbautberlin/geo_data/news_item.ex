defmodule Hierbautberlin.GeoData.NewsItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias Hierbautberlin.GeoData.GeoPlace
  alias Hierbautberlin.GeoData.GeoStreet
  alias Hierbautberlin.GeoData.GeoStreetNumber
  alias Hierbautberlin.GeoData.NewsItem
  alias Hierbautberlin.GeoData.Source

  schema "news_items" do
    field :external_id, :string
    field :title, :string
    field :content, :string
    field :link, :string
    field :published_at, :utc_datetime

    belongs_to :source, Source

    many_to_many :geo_streets, GeoStreet, join_through: "geo_streets_news_items"

    many_to_many :geo_street_numbers, GeoStreetNumber,
      join_through: "geo_street_numbers_news_items"

    many_to_many :geo_places, GeoPlace, join_through: "geo_places_news_items"

    timestamps(type: :utc_datetime)
  end

  def change_associations(%NewsItem{} = news_item, attrs) do
    news_item
    |> cast(%{}, [])
    |> put_assoc(:geo_streets, attrs[:geo_streets])
    |> put_assoc(:geo_street_numbers, attrs[:geo_street_numbers])
    |> put_assoc(:geo_places, attrs[:geo_places])
  end
end
