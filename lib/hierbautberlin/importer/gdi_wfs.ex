defmodule Hierbautberlin.Importer.GdiWfs do
  @moduledoc """
  Reads layers of the WFS services of the Berlin geodata infrastructure
  (https://gdi.berlin.de) as GeoJSON in WGS84 (longitude, latitude).

  The metadata of a dataset is on metaver.de, see `metadata_url/1`. The data is
  licensed under "Datenlizenz Deutschland – Namensnennung – Version 2.0", the
  attribution is "Geoportal Berlin / <name of the dataset>".
  """

  @wfs_base "https://gdi.berlin.de/services/wfs"

  def url(service, layer) do
    query =
      URI.encode_query(%{
        "SERVICE" => "WFS",
        "VERSION" => "2.0.0",
        "REQUEST" => "GetFeature",
        "TYPENAMES" => "#{service}:#{layer}",
        "OUTPUTFORMAT" => "application/json",
        "SRSNAME" => "EPSG:4326"
      })

    "#{@wfs_base}/#{service}?#{query}"
  end

  @doc """
  The features of a layer. Raises when the service doesn't answer with GeoJSON.
  """
  def fetch_features(http_connection, service, layer) do
    response =
      http_connection.get!(url(service, layer), [], timeout: 60_000, recv_timeout: 300_000)

    if response.status_code != 200 do
      raise "#{service}:#{layer} answered with status #{response.status_code}"
    end

    Jason.decode!(response.body)["features"] || []
  end

  @doc """
  The geometry of a feature as `Geo` struct, nil if it has none.
  """
  def geometry(%{"geometry" => geometry}) when is_map(geometry) do
    geometry |> Geo.JSON.decode!() |> Map.put(:srid, 4326)
  end

  def geometry(_feature), do: nil

  def metadata_url(uuid), do: "https://metaver.de/trefferanzeige?docuuid=#{uuid}"
end
