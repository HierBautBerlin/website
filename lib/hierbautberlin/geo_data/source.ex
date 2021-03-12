defmodule Hierbautberlin.GeoData.Source do
  use Ecto.Schema
  import Ecto.Changeset

  schema "sources" do
    field :name, :string
    field :url, :string
    field :copyright, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(source, attrs) do
    source
    |> cast(attrs, [:name, :url, :copyright])
    |> validate_required([:name, :url, :copyright])
  end
end
