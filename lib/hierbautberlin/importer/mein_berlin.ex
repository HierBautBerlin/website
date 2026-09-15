defmodule Hierbautberlin.Importer.MeinBerlin do
  alias Hierbautberlin.GeoData

  def import(http_connection \\ Hierbautberlin.HTTPClient) do
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

    result =
      Enum.map(items, fn item ->
        attrs = to_geo_item(item)

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

  defp to_geo_item(item) do
    point = parse_point(item["point"])
    date = parse_date(item["created_or_modified"])

    Map.merge(
      %{
        external_id: item["url"],
        title: item["title"],
        subtitle: item["organisation"],
        description: item["description"],
        url: "https://mein.berlin.de" <> item["url"],
        state: state(item["status"]),
        geo_point: point,
        # participation_active is also true for plans ("Vorhaben") that are
        # running and for some old projects, only an active phase is reliable
        participation_open: item["type"] != "plan" and is_list(item["active_phase"]),
        date_updated: date
      },
      phase(item, date)
    )
  end

  # Plans ("Vorhaben") have no phases, they are relevant when they changed recently
  defp phase(%{"type" => "plan"}, _updated), do: %{relevance_half_life: 90}

  # Projects: active_phase is [id, "108 Tage", end], future_phase the start and
  # past_phase the end of the participation
  defp phase(%{"active_phase" => [_, _, phase_end]}, updated) do
    phase_end = parse_date(phase_end)
    # phases over years are ongoing processes, not a concrete chance to take part
    long_phase? = DateTime.diff(phase_end, DateTime.utc_now(), :day) > 365

    %{
      date_end: phase_end,
      importance: if(long_phase?, do: 1.5, else: 3.0),
      relevant_from: updated,
      relevant_until: phase_end,
      relevance_half_life: 14
    }
  end

  defp phase(%{"future_phase" => phase_start}, _updated) when is_binary(phase_start) do
    phase_start = parse_date(phase_start)

    %{
      date_start: phase_start,
      importance: 2.0,
      relevant_from: phase_start,
      relevant_until: phase_start,
      relevance_half_life: 14
    }
  end

  defp phase(%{"past_phase" => phase_end}, _updated) when is_binary(phase_end) do
    phase_end = parse_date(phase_end)

    %{
      date_end: phase_end,
      relevant_from: phase_end,
      relevant_until: phase_end,
      relevance_half_life: 90
    }
  end

  defp phase(_item, _updated), do: %{}

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

  # 0: running, 1: starts in the future, 2: finished
  defp state(0), do: "active"
  defp state(1), do: "intended"
  defp state(_), do: "finished"

  defp parse_point(%{"geometry" => %{"type" => "Point"} = point}) do
    [long, lat] = point["coordinates"]
    %Geo.Point{coordinates: {long, lat}, srid: 4326}
  end

  defp parse_point(_) do
    nil
  end

  defp parse_date(nil), do: nil

  defp parse_date(date) do
    case DateTime.from_iso8601(date) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      # older API versions used "2021-01-01 12:00:00.000000+01:00"
      {:error, _} -> Timex.parse!(date, "%Y-%m-%d %k:%M:%S.%f%z:00", :strftime)
    end
  end
end
