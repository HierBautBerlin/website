defmodule Hierbautberlin.Importer.BerlinBebauungsplaene do
  alias Hierbautberlin.Importer.LiqdApi
  alias Hierbautberlin.GeoData

  @state_mapping %{
    "aul" => "in_planning",
    "bbg" => "in_planning",
    "imVerfahren" => "in_planning",
    "festg" => "finished"
  }

  def import(http_connection \\ HTTPoison) do
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

    Enum.map(plans, fn item ->
      attrs = to_geo_item(item, polygons)

      {:ok, geo_item} = GeoData.upsert_geo_item(Map.merge(%{source_id: source.id}, attrs))

      geo_item
    end)
  end

  defp to_geo_item(item, polygons) do
    date =
      [
        parse_date(item["fsg_gvbl_d"]),
        parse_date(item["aul_start"]),
        parse_date(item["aul_ende"]),
        parse_date(item["festsg_am"]),
        parse_date(item["afs_beschl"])
      ]
      |> Enum.filter(&(!is_nil(&1)))
      |> Enum.sort(&(Timex.diff(&1, &2) > 0))
      |> List.first()

    Map.merge(
      %{
        external_id: item["bplanID"],
        title: item["planname"] <> " - " <> item["bereich"],
        url: item["scan_www"] || item["grund_www"],
        geo_geometry: polygons[item["id"]],
        participation_open: Enum.member?(["aul", "bbg", "imVerfahren"], item["status"]),
        state: @state_mapping[item["status"]],
        inserted_at: date,
        updated_at: date
      },
      get_additional_link(item)
    )
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
    Timex.parse!(date, "{YYYY}-{0M}-{0D}")
  rescue
    _ -> nil
  end
end
