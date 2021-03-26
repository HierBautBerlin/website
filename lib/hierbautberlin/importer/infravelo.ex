defmodule Hierbautberlin.Importer.Infravelo do
  alias Hierbautberlin.Importer.KmlParser
  alias Hierbautberlin.Importer.LiqdApi
  alias Hierbautberlin.GeoData

  @state_mapping %{
    "Vorgesehen" => "intended",
    "in Vorbereitung" => "in_preparation",
    "in Planung" => "in_planning",
    "Abgeschlossen" => "finished",
    "in Bau" => "under_construction"
  }

  def import(http_connection \\ HTTPoison) do
    items = LiqdApi.fetch_data(http_connection, "https://www.infravelo.de/api/v1/projects/")

    {:ok, source} =
      GeoData.upsert_source(%{
        short_name: "INFRAVELO",
        name: "infraVelo",
        url: "https://www.infravelo.de/",
        copyright: "infravelo.de / Projekte"
      })

    Enum.map(items, fn item ->
      attrs = to_geo_item(item)

      {:ok, geo_item} = GeoData.upsert_geo_item(Map.merge(%{source_id: source.id}, attrs))

      geo_item
    end)
  end

  defp to_geo_item(item) do
    kml = KmlParser.parse(item["kml"])
    point = KmlParser.extract_point(kml)
    polygon = KmlParser.extract_polygon(kml)

    %{
      external_id: item["id"],
      title: item["title"],
      subtitle: item["subtitle"],
      description: item["description"],
      url: item["link"],
      state: @state_mapping[item["status"]],
      geo_point: point,
      geo_geometry: polygon,
      date_start: parse_start(item["dateStart"]),
      date_end: parse_end(item["dateEnd"])
    }
  end

  defp parse_start(dateStr) do
    case parse_quarter(dateStr) do
      {year, quarter} ->
        {month, day} =
          case quarter do
            "1" -> {1, 1}
            "2" -> {4, 1}
            "3" -> {7, 1}
            "4" -> {10, 1}
          end

        DateTime.new!(Date.new!(year, month, day), ~T[00:00:00], "Europe/Berlin")

      _ ->
        nil
    end
  end

  defp parse_end(dateStr) do
    case parse_quarter(dateStr) do
      {year, quarter} ->
        {month, day} =
          case quarter do
            "1" -> {3, 31}
            "2" -> {6, 30}
            "3" -> {9, 30}
            "4" -> {12, 31}
          end

        DateTime.new!(Date.new!(year, month, day), ~T[00:00:00], "Europe/Berlin")

      _ ->
        nil
    end
  end

  defp parse_quarter(nil) do
    nil
  end

  defp parse_quarter(quarterStr) do
    case Regex.named_captures(~r/(?<quarter>\d*). Quartal (?<year>\d*)/, quarterStr) do
      %{"year" => year, "quarter" => quarter} ->
        {year, _} = Integer.parse(year)
        {year, quarter}

      _ ->
        nil
    end
  end
end
