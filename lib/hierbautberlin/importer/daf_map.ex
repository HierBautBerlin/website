defmodule Hierbautberlin.Importer.DafMap do
  alias Hierbautberlin.GeoData

  def import(http_connection \\ HTTPoison) do
    {:ok, source} =
      GeoData.upsert_source(%{
        short_name: "DAF_MAP",
        name: "Deutsches Architekturforum Berlin",
        url: "https://www.dafmap.de/d/berlin",
        copyright: "Deutsches Architekturforum"
      })

    items =
      fetch_data(
        http_connection,
        "https://www.dafmap.de/d/dafmapgw.py?c=sel&map=berlin"
      )

    result =
      items
      |> Enum.map(&to_geo_item(&1))
      |> Enum.filter(fn item -> item != nil end)
      |> Enum.map(fn item ->
        {:ok, geo_item} = GeoData.upsert_geo_item(Map.merge(%{source_id: source.id}, item))
        geo_item
      end)

    {:ok, result}
  rescue
    error ->
      Bugsnag.report(error)
      {:error, error}
  end

  defp to_geo_item(item) do
    [
      id,
      _,
      name,
      _,
      description,
      _,
      _,
      _,
      _,
      _,
      _,
      _,
      url,
      _,
      _,
      lat,
      long,
      area,
      begin_dt,
      end_dt,
      enabled,
      _,
      upd_sp,
      _,
      _,
      _,
      _,
      _,
      _
    ] = item

    if enabled == 1 do
      geometry =
        if area != "" do
          try do
            coordinates =
              area
              |> String.split(",")
              |> Enum.chunk_every(2)
              |> Enum.map(fn [lat, lng] -> {String.to_float(lng), String.to_float(lat)} end)

            [head | _tail] = coordinates

            coordinates = coordinates ++ [head]

            %Geo.Polygon{
              coordinates: [coordinates],
              srid: 4326
            }
          rescue
            _ -> nil
          end
        else
          nil
        end

      %{
        external_id: Integer.to_string(id),
        title: HtmlEntities.decode(name),
        description: cleanup_description(description),
        url: "https://www.dafmap.de/d/berlin?id=#{id}&mt=0&zoom=17",
        geo_point: %Geo.Point{coordinates: {long, lat}, srid: 4326},
        geometry: geometry,
        additional_link: url,
        additional_link_name: "Deutsches Architekturforum",
        date_start: if(begin_dt, do: Timex.parse!(begin_dt, "{YYYY}-{0M}-{0D}")),
        date_end: if(end_dt, do: Timex.parse!(end_dt, "{YYYY}-{0M}-{0D}")),
        date_updated: if(upd_sp, do: Timex.parse!(upd_sp, "{RFC3339}"))
      }
    else
      nil
    end
  end

  defp fetch_data(http_connection, url) do
    response =
      http_connection.get!(
        url,
        ["User-Agent": "hierbautberlin.de", Referer: "https://www.dafmap.de/d/berlin.html"],
        timeout: 60_000,
        recv_timeout: 60_000
      )

    if response.status_code != 200 do
      []
    else
      Jason.decode!(response.body)["rows"]
    end
  end

  defp cleanup_description(description) do
    description
    |> HtmlEntities.decode()
    |> String.replace(~r/<br>/i, "\n")
    |> String.replace(~r/DAF-Beitrag: \S*/i, "")
    |> String.replace(~r/DAF-Post: \S*/i, "")
    |> String.replace(~r/DAF-Thread \([^)]*\)/, "")
    |> String.replace(~r/DAF-Post \([^)]*\)/, "")
    |> String.replace("Kein DAF-Beitrag vorhanden.", "")
    |> String.replace("Noch kein DAF-Beitrag vorhanden.", "")
    |> String.replace("Kein DAF-Post vorhanden.", "")
    |> String.replace("Noch kein DAF-Post vorhanden.", "")
    |> String.replace(~r/\Anv\z/, "")
    |> String.trim()
  end
end
