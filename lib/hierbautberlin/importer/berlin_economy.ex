defmodule Hierbautberlin.Importer.BerlinEconomy do
  alias Hierbautberlin.GeoData

  def import(http_connection \\ HTTPoison) do
    {:ok, source} =
      GeoData.upsert_source(%{
        short_name: "BERLIN_ECONOMY",
        name: "Neubauprojekte in Berlin",
        url: "https://www.berlin.de/wirtschaft/bauprojekte/",
        copyright: "Stadt Berlin"
      })

    items =
      fetch_data(
        http_connection,
        "https://www.berlin.de/wirtschaft/bauprojekte/rubric.geojson?_rnd=448764"
      )

    Enum.map(items, fn item ->
      attrs = to_geo_item(item)

      {:ok, geo_item} = GeoData.upsert_geo_item(Map.merge(%{source_id: source.id}, attrs))

      geo_item
    end)
  end

  defp to_geo_item(item) do
    point = parse_point(item["geometry"])
    date = Timex.parse!(item["properties"]["modified"], "{RFC3339}")

    %{
      external_id: item["properties"]["url"],
      title: item["properties"]["title"],
      description: item["properties"]["description"],
      url: item["properties"]["url"],
      geo_point: point,
      date_updated: date
    }
  end

  defp fetch_data(http_connection, url) do
    response =
      http_connection.get!(
        url,
        ["User-Agent": "hierbautberlin.de"],
        timeout: 60_000,
        recv_timeout: 60_000
      )

    if response.status_code != 200 do
      []
    else
      Jason.decode!(response.body)["features"]
    end
  end

  defp parse_point(%{"type" => "Point"} = point) do
    [long, lat] = point["coordinates"]
    %Geo.Point{coordinates: {long, lat}, srid: 4326}
  end

  defp parse_point(_) do
    nil
  end
end
