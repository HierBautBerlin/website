defmodule Hierbautberlin.GeoData do
  import Ecto.Query, warn: false

  alias Hierbautberlin.Repo
  alias Hierbautberlin.GeoData.Source
  alias Hierbautberlin.GeoData.GeoItem

  def get_source!(id) do
    Repo.get!(Source, id)
  end

  def upsert_source(attrs \\ %{}) do
    %Source{}
    |> Source.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: :short_name
    )
  end

  def get_geo_item!(id) do
    Repo.get!(GeoItem, id)
    |> Repo.preload([:source])
  end

  def create_geo_item(attrs \\ %{}) do
    %GeoItem{}
    |> GeoItem.changeset(attrs)
    |> Repo.insert()
  end

  def change_geo_item(%GeoItem{} = geo_item), do: GeoItem.changeset(geo_item, %{})

  def upsert_geo_item(attrs \\ %{}) do
    %GeoItem{}
    |> GeoItem.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:source_id, :external_id]
    )
  end

  def get_point(geo_item)

  def get_point(%{geo_point: item}) when not is_nil(item) do
    %{coordinates: {lng, lat}} = item
    %{lat: lat, lng: lng}
  end

  def get_point(%{geo_geometry: geometry}) when not is_nil(geometry) do
    %{coordinates: {lng, lat}} = Geo.Turf.Measure.center(geometry)
    %{lat: lat, lng: lng}
  end

  def get_point(_item) do
    %{lat: nil, lng: nil}
  end

  def get_items_near(lat, lng, count \\ 10) do
    geom = %Geo.Point{
      coordinates: {lng, lat},
      properties: %{},
      srid: 4326
    }

    query =
      from item in GeoItem,
        limit: ^count,
        order_by:
          fragment(
            "case when geo_geometry is not null then ST_Distance(geo_geometry,?) else ST_Distance(geo_point, ?) end",
            ^geom,
            ^geom
          )

    query
    |> Repo.all()
    |> Repo.preload(:source)
    |> remove_old_items()
    |> sort_by_relevance(%{lat: lat, lng: lng})
  end

  defp remove_old_items(items) do
    Enum.filter(items, fn item ->
      date = GeoItem.newest_date(item)

      date == nil || Timex.after?(date, Timex.shift(Timex.today(), years: -5))
    end)
  end

  defp sort_by_relevance(items, %{lat: lat, lng: lng}) do
    Enum.sort_by(items, fn item ->
      date = GeoItem.newest_date(item)

      months_difference =
        Timex.diff(Timex.now(), date || Timex.shift(Timex.today(), months: -3), :months)

      %{lat: item_lat, lng: item_lng} = get_point(item)

      distance =
        Geo.Turf.Measure.distance(
          %Geo.Point{coordinates: {lng, lat}},
          %Geo.Point{coordinates: {item_lng, item_lat}},
          :meters
        )

      push_factor =
        if item.participation_open do
          30
        else
          0
        end

      distance / 10 + months_difference - push_factor
    end)
  end
end
