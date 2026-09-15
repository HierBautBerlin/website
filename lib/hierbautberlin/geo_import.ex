defmodule Hierbautberlin.GeoImport do
  @moduledoc """
  Imports the geo objects (streets, street numbers, places) the text analysis
  and the map are based on.

  In production (releases have no mix) run:

      bin/hierbautberlin eval 'Hierbautberlin.Release.import_geo_data("/path/berlin-latest.osm.pbf")'
  """

  alias Hierbautberlin.GeoData.MapFeatures
  alias Hierbautberlin.GeoImport.{OSM, Places}

  def import_osm(file, opts \\ []) do
    stats = OSM.import(file, opts)
    MapFeatures.refresh()
    stats
  end

  def import_places(types \\ Places.types()) do
    stats = Places.import(types)
    OSM.update_news_item_geometries()
    MapFeatures.refresh()
    stats
  end
end
