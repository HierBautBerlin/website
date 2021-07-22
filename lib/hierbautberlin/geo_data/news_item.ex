defmodule Hierbautberlin.GeoData.NewsItem do
  use Ecto.Schema
  import Ecto.Query, warn: false
  import Ecto.Changeset

  alias Geo.PostGIS.Geometry
  alias Hierbautberlin.Repo

  alias Hierbautberlin.GeoData.{
    GeoPlace,
    GeoPosition,
    GeoStreet,
    GeoStreetNumber,
    GeoMapItem,
    NewsItem,
    Source
  }

  schema "news_items" do
    field :external_id, :string
    field :title, :string
    field :content, :string
    field :url, :string
    field :published_at, :utc_datetime
    field :geometries, Geometry
    field :geo_points, Geometry
    field :hidden, :boolean, default: false

    belongs_to :source, Source

    many_to_many :geo_streets, GeoStreet,
      join_through: "geo_streets_news_items",
      on_replace: :delete

    many_to_many :geo_street_numbers, GeoStreetNumber,
      join_through: "geo_street_numbers_news_items",
      on_replace: :delete

    many_to_many :geo_places, GeoPlace, join_through: "geo_places_news_items", on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def changeset(news_item, attrs) do
    news_item
    |> cast(attrs, [:external_id, :title, :content, :url, :published_at, :source_id, :hidden])
    |> unique_constraint(:external_id)
  end

  def change_associations(%NewsItem{} = news_item, attrs) do
    news_item
    |> cast(%{}, [])
    |> put_assoc(:geo_streets, attrs[:geo_streets])
    |> put_assoc(:geo_street_numbers, attrs[:geo_street_numbers])
    |> put_assoc(:geo_places, attrs[:geo_places])
    |> update_cached_geometries()
  end

  def update_all_geometries() do
    NewsItem
    |> Repo.all()
    |> Repo.preload([:geo_streets, :geo_street_numbers, :geo_places])
    |> Enum.each(fn news_item ->
      news_item
      |> update_cached_geometries()
      |> Repo.update!()
    end)
  end

  def update_cached_geometries(news_item) do
    changeset = cast(news_item, %{}, [])

    geo_streets = get_field(changeset, :geo_streets)
    geo_street_numbers = get_field(changeset, :geo_street_numbers)
    geo_places = get_field(changeset, :geo_places)

    changeset
    |> put_change(:geometries, join_geometries([geo_streets, geo_places]))
    |> put_change(:geo_points, join_geo_points([geo_streets, geo_street_numbers, geo_places]))
  end

  defp join_geometries(geometries) do
    collection =
      geometries
      |> List.flatten()
      |> Enum.filter(fn item -> !is_nil(item.geometry) end)
      |> Enum.map(fn item ->
        item.geometry
      end)

    if Enum.empty?(collection) do
      nil
    else
      %Geo.GeometryCollection{
        geometries: collection,
        srid: 4326
      }
    end
  end

  defp join_geo_points(geometries) do
    coordinates =
      geometries
      |> List.flatten()
      |> Enum.filter(fn item -> !is_nil(item.geo_point) end)
      |> Enum.map(fn item ->
        item.geo_point.coordinates
      end)

    if Enum.empty?(coordinates) do
      nil
    else
      %Geo.MultiPoint{
        coordinates: coordinates,
        srid: 4326
      }
    end
  end

  def get_near(lat, lng, count) do
    geom = %Geo.Point{
      coordinates: {lng, lat},
      properties: %{},
      srid: 4326
    }

    query =
      from item in NewsItem,
        where: not (is_nil(item.geometries) and is_nil(item.geo_points)),
        limit: ^count,
        where: item.hidden == false,
        where:
          fragment(
            "ST_DWithin(geometries, ?, 0.05 ) or ST_DWithin(geo_points, ?, 0.05 )",
            ^geom,
            ^geom
          ),
        order_by:
          fragment(
            "LEAST(ST_Distance(geometries, ?),ST_Distance(geo_points, ?))",
            ^geom,
            ^geom
          )

    query
    |> Repo.all()
    |> Repo.preload([:source, :geo_streets, :geo_street_numbers, :geo_places])
    |> Enum.map(fn item ->
      %GeoMapItem{
        type: :news_item,
        id: item.id,
        title: item.title,
        description: item.content,
        positions: get_positions_for_item(item),
        newest_date: item.published_at,
        source: item.source,
        url: item.url,
        participation_open: false,
        item: item
      }
    end)
  end

  defp get_positions_for_item(item) do
    (Enum.map(item.geo_streets, fn geo_street ->
       %GeoPosition{
         type: :geo_street,
         id: geo_street.id,
         geopoint: geo_street.geo_point,
         geometry: geo_street.geometry
       }
     end) ++
       Enum.map(item.geo_street_numbers, fn geo_street_number ->
         %GeoPosition{
           type: :geo_street_number,
           id: geo_street_number.id,
           geopoint: geo_street_number.geo_point
         }
       end) ++
       Enum.map(item.geo_places, fn geo_place ->
         %GeoPosition{
           type: :geo_place,
           id: geo_place.id,
           geopoint: geo_place.geo_point,
           geometry: geo_place.geometry
         }
       end))
    |> Enum.filter(fn position ->
      !is_nil(position.geopoint) || !is_nil(position.geometry)
    end)
  end
end
