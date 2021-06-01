defmodule Hierbautberlin.Importer.MeinBerlin do
  alias Hierbautberlin.GeoData

  def import(http_connection \\ HTTPoison) do
    {:ok, source} =
      GeoData.upsert_source(%{
        short_name: "MEIN_BERLIN",
        name: "meinBerlin",
        url: "https://mein.berlin.de/",
        copyright: "Stadt Berlin"
      })

    items =
      fetch_data(http_connection, "https://mein.berlin.de/api/projects/?format=json") ++
        fetch_data(http_connection, "https://mein.berlin.de/api/plans/?format=json")

    Enum.map(items, fn item ->
      attrs = to_geo_item(item)

      {:ok, geo_item} = GeoData.upsert_geo_item(Map.merge(%{source_id: source.id}, attrs))

      geo_item
    end)
  end

  defp to_geo_item(item) do
    point = parse_point(item["point"])
    date = parse_date(item["created_or_modified"])

    %{
      external_id: item["url"],
      title: item["title"],
      subtitle: item["organisation"],
      description: item["description"],
      url: "https://mein.berlin.de" <> item["url"],
      state: if(item["status"] == 0, do: "active", else: "finished"),
      geo_point: point,
      participation_open: if(item["participation"] == 0, do: true, else: false),
      inserted_at: date,
      updated_at: date
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
      Jason.decode!(response.body)
    end
  end

  defp parse_point(%{"geometry" => %{"type" => "Point"} = point}) do
    [long, lat] = point["coordinates"]
    %Geo.Point{coordinates: {long, lat}, srid: 4326}
  end

  defp parse_point(_) do
    nil
  end

  defp parse_date(date) do
    Timex.parse!(date, "%Y-%m-%d %k:%M:%S.%f%z:00", :strftime)
  end
end
