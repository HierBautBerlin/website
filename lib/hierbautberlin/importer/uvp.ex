defmodule Hierbautberlin.Importer.UVP do
  @moduledoc """
  Imports environmental impact assessments (UVP) from the UVP-Verbund portal.

  The portal serves all of Germany, only procedures within the Berlin area are
  imported.
  """
  alias Hierbautberlin.GeoData

  @base_url "https://www.uvp-verbund.de/rest/getMapMarkers"

  # Zulassungsverfahren, Ausländische Vorhaben, Raumordnungsverfahren,
  # Linienbestimmungen, Negative Vorprüfungen
  @legends ~w(obj_class_zv obj_class_av obj_class_ro obj_class_li obj_class_nv)

  # Berlin including a small margin (min lng, min lat, max lng, max lat)
  @bbox {13.08, 52.33, 13.77, 52.68}

  @max_pages 500

  def import(http_connection \\ Hierbautberlin.HTTPClient, opts \\ []) do
    delay = Keyword.get(opts, :delay, 1_000)

    {:ok, source} =
      GeoData.upsert_source(%{
        short_name: "UVP",
        name: "UVP - Umweltverträglichkeitsprüfung",
        url: "https://www.uvp-verbund.de/kartendienste",
        copyright: "Freie und Hansestadt Hamburg - Landesbetrieb Geoinformation und Vermessung"
      })

    result =
      @legends
      |> Enum.flat_map(&fetch_markers(http_connection, &1, delay))
      |> Enum.map(&to_geo_item/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(& &1.external_id)
      |> Enum.map(fn attrs ->
        {:ok, geo_item} = GeoData.upsert_geo_item(Map.merge(%{source_id: source.id}, attrs))
        geo_item
      end)

    # Older imports contained the procedures of all of Germany
    GeoData.hide_geo_items_outside(source, @bbox)
    GeoData.hide_missing_geo_items(source, Enum.map(result, & &1.external_id))

    {:ok, result}
  rescue
    error ->
      Bugsnag.report(error)
      {:error, error}
  end

  defp to_geo_item(%{"uuid" => uuid, "title" => title} = marker) do
    with {lat, _} <- Float.parse(to_string(marker["lat"])),
         {lng, _} <- Float.parse(to_string(marker["lon"])),
         true <- in_bbox?(lng, lat) do
      %{
        external_id: uuid,
        title: String.trim(title),
        subtitle: marker["procedure"],
        url: "https://www.uvp-verbund.de/trefferanzeige?docuuid=" <> uuid,
        geo_point: %Geo.Point{coordinates: {lng, lat}, srid: 4326}
      }
    else
      _ -> nil
    end
  end

  defp to_geo_item(_marker), do: nil

  defp in_bbox?(lng, lat) do
    {min_lng, min_lat, max_lng, max_lat} = @bbox
    lng >= min_lng and lng <= max_lng and lat >= min_lat and lat <= max_lat
  end

  defp fetch_markers(http_connection, legend, delay, page \\ 1)

  defp fetch_markers(_http_connection, _legend, _delay, page) when page > @max_pages, do: []

  defp fetch_markers(http_connection, legend, delay, page) do
    if page > 1, do: Process.sleep(delay)

    response =
      http_connection.get!(
        "#{@base_url}?legend=#{legend}&page=#{page}",
        ["User-Agent": "hierbautberlin.de"],
        timeout: 60_000,
        recv_timeout: 60_000
      )

    with 200 <- response.status_code,
         {:ok, [_ | _] = markers} <- Jason.decode(response.body) do
      markers ++ fetch_markers(http_connection, legend, delay, page + 1)
    else
      _ -> []
    end
  end
end
