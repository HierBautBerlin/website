defmodule Hierbautberlin.GeoData do
  import Ecto.Query, warn: false
  alias Hierbautberlin.Repo

  alias Hierbautberlin.GeoData.Source
  alias Hierbautberlin.GeoData.GeoItem

  def get_source(id) do
    Repo.get!(Source, id)
  end

  def get_geo_item(id) do
    Repo.get!(GeoItem, id)
  end

  def create_geo_item(attrs \\ %{}) do
    %GeoItem{}
    |> GeoItem.changeset(attrs)
    |> Repo.insert()
  end

  def change_geo_item(%GeoItem{} = geo_item), do: GeoItem.changeset(geo_item, %{})
end
