defmodule Hierbautberlin.Importer.UVP do
  alias Hierbautberlin.GeoData

  def import(http_connection \\ HTTPoison) do
    {:ok, source} =
      GeoData.upsert_source(%{
        short_name: "UVP",
        name: "UVP - Umweltverträglichkeitsprüfung",
        url: "https://www.uvp-verbund.de/kartendienste",
        copyright: "Freie und Hansestadt Hamburg - Landesbetrieb Geoinformation und Vermessung"
      })

    items =
      fetch_data(
        http_connection,
        "https://www.uvp-verbund.de/portal/_ns:ZzMwX18zMXxpbWFya2VyNA__/main-maps.psml"
      )

    Enum.map(items, fn item ->
      attrs = to_geo_item(item)

      {:ok, geo_item} = GeoData.upsert_geo_item(Map.merge(%{source_id: source.id}, attrs))

      geo_item
    end)
  end

  defp to_geo_item(item) do
    [lat, long, title, uuid, _, _, _, _] = item

    %{
      external_id: uuid,
      title: title,
      url: "https://www.uvp-verbund.de/trefferanzeige?docuuid=" <> uuid,
      geo_point: %Geo.Point{coordinates: {long, lat}, srid: 3857}
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
      response.body
      |> String.replace(~r/^var markers = /, "")
      |> String.replace(~r/;$/, "")
      |> Jason.decode!()
    end
  end
end
