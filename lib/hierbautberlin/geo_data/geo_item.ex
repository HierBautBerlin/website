defmodule Hierbautberlin.GeoData.GeoItem do
  use Ecto.Schema
  import Ecto.Query, warn: false
  import Ecto.Changeset

  alias Hierbautberlin.Repo
  alias Hierbautberlin.GeoData.{GeoItem, GeoPosition, GeoMapItem, Source}

  @states [
    "intended",
    "in_preparation",
    "in_planning",
    "under_construction",
    "active",
    "finished",
    nil
  ]

  schema "geo_items" do
    field :external_id, :string
    field :title, :string
    field :subtitle, :string
    field :description, :string
    field :url, :string
    field :state, :string
    field :date_start, :utc_datetime
    field :date_end, :utc_datetime
    field :date_updated, :utc_datetime
    field :geo_point, Geo.PostGIS.Geometry
    field :geometry, Geo.PostGIS.Geometry
    field :participation_open, :boolean, default: false
    field :additional_link, :string
    field :additional_link_name, :string
    field :hidden, :boolean, default: false

    belongs_to :source, Source

    timestamps(type: :utc_datetime)
  end

  def changeset(geo_item, attrs) do
    geo_item
    |> cast(attrs, [
      :external_id,
      :title,
      :subtitle,
      :description,
      :url,
      :state,
      :date_start,
      :date_end,
      :date_updated,
      :geo_point,
      :geometry,
      :source_id,
      :participation_open,
      :additional_link,
      :additional_link_name,
      :inserted_at,
      :updated_at,
      :hidden
    ])
    |> validate_inclusion(:state, @states)
    |> validate_required([:source_id, :external_id, :title])
    |> unique_constraint([:source_id, :external_id])
  end

  def newest_date(geo_item) do
    [
      geo_item.date_start,
      geo_item.date_end,
      geo_item.date_updated
    ]
    |> Enum.filter(&(!is_nil(&1)))
    |> Enum.sort(&(Timex.diff(&1, &2) > 0))
    |> List.first()
  end

  def get_near(lat, lng, count) do
    geom = %Geo.Point{
      coordinates: {lng, lat},
      properties: %{},
      srid: 4326
    }

    query =
      from item in GeoItem,
        limit: ^count,
        where: item.hidden == false,
        where:
          fragment(
            "(geometry is not null and ST_DWithin(geometry, ?, 0.015 )) or (geo_point is not null and ST_DWithin(geo_point, ?, 0.015 ))",
            ^geom,
            ^geom
          ),
        order_by:
          fragment(
            "ST_Distance(COALESCE(geometry, geo_point), ?)",
            ^geom
          )

    query
    |> Repo.all()
    |> Repo.preload(:source)
    |> Enum.map(fn item ->
      %GeoMapItem{
        type: :geo_item,
        id: item.id,
        title: item.title,
        subtitle: item.subtitle,
        description: item.description,
        positions: [
          %GeoPosition{
            type: :geo_item,
            id: item.id,
            geopoint: item.geo_point,
            geometry: item.geometry
          }
        ],
        newest_date: newest_date(item),
        source: item.source,
        url: item.url,
        participation_open: item.participation_open,
        item: item
      }
    end)
  end
end
