defmodule Hierbautberlin.GeoData.NewsItem do
  use Ecto.Schema
  import Ecto.Query, warn: false
  import Ecto.Changeset

  alias Geo.PostGIS.Geometry
  alias Hierbautberlin.Repo

  alias Hierbautberlin.GeoData.{
    GeoPlace,
    GeoStreet,
    GeoStreetNumber,
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
    # the text and districts the addresses were found in, used to analyze it again
    field :full_text, :string
    field :districts, {:array, :string}, default: []
    # streets that were mentioned with a house number we could not resolve. They
    # are linked for context, but contribute no geometry and no point.
    field :context_street_ids, {:array, :integer}, default: []
    # see Hierbautberlin.GeoData.Relevance
    field :importance, :float, default: 1.0
    field :relevant_from, :utc_datetime
    field :relevant_until, :utc_datetime
    field :relevance_half_life, :integer, default: 30

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
    |> cast(attrs, [
      :external_id,
      :title,
      :content,
      :url,
      :published_at,
      :source_id,
      :hidden,
      :full_text,
      :districts,
      :importance,
      :relevant_from,
      :relevant_until,
      :relevance_half_life
    ])
    |> unique_constraint(:external_id)
  end

  def change_associations(%NewsItem{} = news_item, attrs) do
    geo_streets = attrs[:geo_streets] || []
    street_ids = MapSet.new(geo_streets, & &1.id)

    context_streets =
      Enum.reject(attrs[:context_streets] || [], &MapSet.member?(street_ids, &1.id))

    news_item
    |> cast(%{}, [])
    |> put_change(:context_street_ids, Enum.map(context_streets, & &1.id))
    |> put_assoc(:geo_streets, Enum.uniq_by(geo_streets ++ context_streets, & &1.id))
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

    context_ids = MapSet.new(get_field(changeset, :context_street_ids) || [])
    geo_streets = get_field(changeset, :geo_streets)
    geo_street_numbers = get_field(changeset, :geo_street_numbers)
    geo_places = get_field(changeset, :geo_places)

    # A street that was only mentioned with a house number we could not resolve
    # keeps its point, so the item stays findable on the map, but not its
    # geometry - drawing the whole street would claim all of it is meant.
    drawn_streets = Enum.reject(geo_streets, &MapSet.member?(context_ids, &1.id))

    changeset
    |> put_change(:geometries, join_geometries([drawn_streets, geo_places]))
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
end
