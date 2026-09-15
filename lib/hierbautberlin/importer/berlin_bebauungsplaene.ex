defmodule Hierbautberlin.Importer.BerlinBebauungsplaene do
  alias Hierbautberlin.Importer.LiqdApi
  alias Hierbautberlin.GeoData

  @state_mapping %{
    "aul" => "in_planning",
    "bbg" => "in_planning",
    "imVerfahren" => "in_planning",
    "festg" => "finished"
  }

  def import(http_connection \\ Hierbautberlin.HTTPClient) do
    {:ok, source} =
      GeoData.upsert_source(%{
        short_name: "BERLIN_BEBAUUNGSPLAENE",
        name: "Berlin Bebauungspläne",
        url: "https://www.stadtentwicklung.berlin.de/planen/b-planverfahren/berlin/index.shtml",
        copyright: "Stadt Berlin"
      })

    polygons =
      LiqdApi.fetch_data(
        http_connection,
        "https://bplan-prod.liqd.net/api/bplan/multipolygons/?format=json",
        "features"
      )
      |> Enum.map(fn item ->
        {item["properties"]["pk"], Map.put(Geo.JSON.decode!(item["geometry"]), :srid, 4326)}
      end)
      |> Map.new()

    plans =
      LiqdApi.fetch_data(
        http_connection,
        "https://bplan-prod.liqd.net/api/bplan/data/?format=json"
      )

    result =
      Enum.map(plans, fn item ->
        attrs = to_geo_item(item, polygons)

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

  defp to_geo_item(item, polygons) do
    dates =
      [
        parse_date(item["fsg_gvbl_d"]),
        parse_date(item["aul_anfang"]),
        parse_date(item["aul_ende"]),
        parse_date(item["festsg_am"]),
        parse_date(item["afs_beschl"])
      ]
      |> Enum.filter(&(!is_nil(&1)))
      |> Enum.sort(&(Timex.diff(&1, &2) > 0))

    display_period = display_period(item)

    Map.merge(
      %{
        external_id: item["bplanID"],
        title: item["planname"] <> " - " <> item["bereich"],
        url: item["scan_www"] || item["grund_www"],
        geometry: polygons[item["id"]],
        participation_open: display_period != nil and display_period.open,
        state: @state_mapping[item["status"]],
        date_start: List.last(dates),
        date_end: List.first(dates)
      },
      get_additional_link(item)
    )
    |> Map.merge(display_relevance(display_period))
  end

  # During the public display ("Auslegung") everyone can comment on the plan
  defp display_period(item) do
    with %DateTime{} = from <- parse_date(item["aul_anfang"]),
         %DateTime{} = until <- parse_date(item["aul_ende"]) do
      until = Timex.end_of_day(until)
      now = DateTime.utc_now()

      %{
        from: from,
        until: until,
        open: DateTime.compare(from, now) != :gt and DateTime.compare(until, now) != :lt
      }
    else
      _ -> nil
    end
  end

  defp display_relevance(nil), do: %{}

  defp display_relevance(%{from: from, until: until}) do
    if DateTime.compare(until, DateTime.utc_now()) == :lt do
      %{}
    else
      %{importance: 3.0, relevant_from: from, relevant_until: until, relevance_half_life: 14}
    end
  end

  defp get_additional_link(%{"scan_www" => scan, "grund_www" => grund}) do
    if !is_nil(scan) && String.length(scan) > 0 && !is_nil(grund) && String.length(grund) > 0 do
      %{
        additional_link: grund,
        additional_link_name: "Begründung"
      }
    else
      %{}
    end
  end

  defp get_additional_link(_) do
    %{}
  end

  defp parse_date(date) do
    date |> Timex.parse!("{YYYY}-{0M}-{0D}") |> DateTime.from_naive!("Etc/UTC")
  rescue
    _ -> nil
  end
end
