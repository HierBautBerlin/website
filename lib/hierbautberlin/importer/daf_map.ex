defmodule Hierbautberlin.Importer.DafMap do
  @moduledoc """
  Imports the construction projects of the DAF-Karte (Deutsches Architekturforum).

  The project list only contains names, positions and dates. Description and
  links are loaded per project, but only for projects that changed since the
  last import.
  """
  import Ecto.Query, warn: false

  alias Hierbautberlin.GeoData
  alias Hierbautberlin.GeoData.GeoItem
  alias Hierbautberlin.Repo

  @base_url "https://dafmap.de"
  @headers ["User-Agent": "hierbautberlin.de", "X-Requested-By": "dafmapV2"]

  @state_mapping %{
    "planned" => "in_planning",
    "uc" => "under_construction",
    "done" => "finished"
  }

  def import(http_connection \\ Hierbautberlin.HTTPClient) do
    {:ok, source} =
      GeoData.upsert_source(%{
        short_name: "DAF_MAP",
        name: "Deutsches Architekturforum",
        url: "#{@base_url}/berlin",
        copyright: "Deutsches Architekturforum"
      })

    known_updates = known_updates(source)

    result =
      http_connection
      |> fetch_json("#{@base_url}/serve/projects/berlin")
      |> List.wrap()
      |> Enum.map(fn project ->
        updated = parse_datetime(project["updated"])
        id = to_string(project["id"])

        details =
          if Map.get(known_updates, id) == updated do
            nil
          else
            fetch_json(http_connection, "#{@base_url}/serve/project/#{id}")
          end

        attrs = to_geo_item(project, details, updated)
        {:ok, geo_item} = GeoData.upsert_geo_item(Map.merge(%{source_id: source.id}, attrs))
        geo_item
      end)

    GeoData.hide_missing_geo_items(source, Enum.map(result, & &1.external_id))

    {:ok, result}
  rescue
    error ->
      Bugsnag.report(error)
      {:error, error}
  end

  defp known_updates(source) do
    from(item in GeoItem,
      where: item.source_id == ^source.id,
      select: {item.external_id, item.date_updated}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp to_geo_item(project, details, updated) do
    id = to_string(project["id"])

    %{
      external_id: id,
      title: HtmlEntities.decode(project["name"]),
      url: "#{@base_url}/berlin?id=#{id}&mt=0&zoom=17",
      state: @state_mapping[project["status"]],
      geo_point: to_point(project["location"]),
      geometry: to_polygon(project["area"]),
      date_start: parse_date(project["cBegin"]),
      date_end: parse_date(project["cEnd"]),
      date_updated: updated
    }
    |> Map.merge(details_attrs(details))
  end

  # Without details (unchanged project) the stored description and links are kept
  defp details_attrs(nil), do: %{}

  defp details_attrs(details) do
    daf_link =
      (get_in(details, ["urls", "daf"]) || [])
      |> Enum.find(&(is_binary(&1) and String.contains?(&1, "/thread/")))

    %{
      description: cleanup_description(details["description"]),
      additional_link: daf_link,
      additional_link_name: if(daf_link, do: "Deutsches Architekturforum")
    }
  end

  defp to_point(%{"type" => "Point", "coordinates" => [lng, lat]}) do
    %Geo.Point{coordinates: {lng, lat}, srid: 4326}
  end

  defp to_point(_), do: nil

  defp to_polygon(%{"type" => type} = geometry) when type in ["Polygon", "MultiPolygon"] do
    geometry |> Geo.JSON.decode!() |> Map.put(:srid, 4326)
  end

  defp to_polygon(_), do: nil

  defp fetch_json(http_connection, url) do
    response = http_connection.get!(url, @headers, timeout: 60_000, recv_timeout: 60_000)

    if response.status_code == 200 do
      Jason.decode!(response.body)
    end
  end

  defp parse_date(nil), do: nil

  defp parse_date(date) do
    case Date.from_iso8601(date) do
      {:ok, date} -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
      _ -> nil
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(datetime) do
    case NaiveDateTime.from_iso8601(datetime) do
      {:ok, naive} -> naive |> DateTime.from_naive!("Etc/UTC") |> DateTime.truncate(:second)
      _ -> nil
    end
  end

  defp cleanup_description(nil), do: nil

  defp cleanup_description(description) do
    description
    |> HtmlEntities.decode()
    |> String.replace(~r/<br\/?>/i, "\n")
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
    |> case do
      "" -> nil
      text -> text
    end
  end
end
