defmodule Hierbautberlin.GeoData.Source do
  use Ecto.Schema
  import Ecto.Changeset

  alias Hierbautberlin.GeoData.GeoItem

  schema "sources" do
    field :short_name, :string
    field :name, :string
    field :url, :string
    field :copyright, :string
    field :color, :string

    has_many :geo_items, GeoItem

    timestamps(type: :utc_datetime)
  end

  def changeset(source, attrs) do
    source
    |> cast(attrs, [:short_name, :name, :url, :copyright, :color])
    |> validate_required([:short_name, :name, :url, :copyright])
    |> unique_constraint([:short_name])
  end
end
