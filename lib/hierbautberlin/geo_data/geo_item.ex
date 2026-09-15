defmodule Hierbautberlin.GeoData.GeoItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias Hierbautberlin.GeoData.Source

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
    # see Hierbautberlin.GeoData.Relevance
    field :importance, :float, default: 1.0
    field :relevant_from, :utc_datetime
    field :relevant_until, :utc_datetime
    field :relevance_half_life, :integer, default: 30

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
      :hidden,
      :importance,
      :relevant_from,
      :relevant_until,
      :relevance_half_life
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
    |> Enum.sort_by(&abs(Timex.diff(&1, Timex.now(), :days)))
    |> List.first()
  end
end
