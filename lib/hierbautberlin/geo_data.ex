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

  def get_items_near(lat, long, count \\ 10) do
    geom = %Geo.Point{
      coordinates: {long, lat},
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
  end
end
