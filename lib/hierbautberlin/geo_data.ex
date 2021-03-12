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
end
