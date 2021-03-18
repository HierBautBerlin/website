defmodule Hierbautberlin.Importer.Infravelo do
  alias Hierbautberlin.Importer.KmlParser

  def import(http_connection \\ HTTPoison) do
    items = fetch_data(http_connection, "https://www.infravelo.de/api/v1/projects/")

    Enum.map(items, fn item ->
      {:ok, geo_item} =
        item
        |> to_geo_item()
        |> Hierbautberlin.GeoData.create_geo_item()

      geo_item
    end)
  end

  defp fetch_data(http_connection, url, prev_result \\ []) do
    response = http_connection.get!(url)

    if response.status_code != 200 do
      prev_result
    else
      json = Jason.decode!(response.body)

      result = prev_result ++ json["results"]

      if json["next"] do
        fetch_data(http_connection, json["next"], result)
      else
        result
      end
    end
  end

  defp to_geo_item(item) do
    kml = KmlParser.parse(item["kml"])
    point = KmlParser.extract_point(kml)
    polygon = KmlParser.extract_polygon(kml)

    %{
      title: item["title"],
      url: item["link"],
      geo_point: point,
      geo_geometry: polygon
    }
  end
end
