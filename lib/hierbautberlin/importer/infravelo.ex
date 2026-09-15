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

  def import(http_connection \\ Hierbautberlin.HTTPClient) do
    items = LiqdApi.fetch_data(http_connection, "https://www.infravelo.de/api/v1/projects/")

    {:ok, source} =
      GeoData.upsert_source(%{
        short_name: "INFRAVELO",
        name: "infraVelo",
        url: "https://www.infravelo.de/",
        copyright: "infravelo.de / Projekte"
      })

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
    kml = KmlParser.parse(item["kml"])
    point = KmlParser.extract_point(kml)
    polygon = KmlParser.extract_polygon(kml)
    {date_start, date_end} = dates(item)

    %{
      external_id: item["id"],
      title: clean_line(item["title"]),
      subtitle: clean_line(item["subtitle"]),
      description: description(item),
      url: item["link"],
      state: @state_mapping[item["status"]],
      geo_point: point,
      geometry: polygon,
      date_start: date_start,
      date_end: date_end,
      importance: importance(item)
    }
  end

  @bike_parking ["Anlehnbügel", "Lastenfahrradbügel", "Elektrokleinstfahrzeuge", "Fahrradbox"]

  # Most projects are a few bike stands, those are small details
  defp importance(item) do
    types = Enum.map(item["types"] || [], &clean(&1["type"]))

    cond do
      types != [] and Enum.all?(types, &(&1 in @bike_parking)) -> 0.3
      @state_mapping[item["status"]] == "under_construction" -> 1.5
      true -> 1.0
    end
  end

  # Most projects (e.g. bike stands) only have the year of implementation,
  # some only milestones with quarters.
  defp dates(item) do
    milestone_quarters =
      (item["milestones"] || [])
      |> Enum.map(&parse_quarter(&1["date"]))
      |> Enum.reject(&is_nil/1)

    cond do
      parse_quarter(item["dateStart"]) || parse_quarter(item["dateEnd"]) ->
        {quarter_start(parse_quarter(item["dateStart"])),
         quarter_end(parse_quarter(item["dateEnd"]))}

      is_integer(item["yearOfImplementation"]) ->
        year = item["yearOfImplementation"]
        {quarter_start({year, "1"}), quarter_end({year, "4"})}

      milestone_quarters != [] ->
        {quarter_start(Enum.min(milestone_quarters)), quarter_end(Enum.max(milestone_quarters))}

      true ->
        {nil, nil}
    end
  end

  # The "Kurzinfo" box of the project page. Many projects have no description
  # at all, then this is the only information about them.
  defp description(item) do
    types =
      Enum.map(item["types"] || [], fn type ->
        name = [type["type"], type["name"]] |> Enum.map(&clean/1) |> Enum.reject(&blank?/1)

        metrics =
          Enum.map_join(
            type["metrics"] || [],
            ", ",
            &"#{clean(&1["name"])}: #{clean(&1["value"])}"
          )

        "Projekttyp: #{Enum.join(name, ", ")}" <> if(metrics == "", do: "", else: " (#{metrics})")
      end)

    districts = Enum.map_join(item["districts"] || [], ", ", &clean(&1["name"]))

    facts =
      [
        {"Bezirk", districts},
        {"Vorhabenträger", clean(item["holder"])},
        {"Bauherr", clean(item["owner"])},
        {"Jahr der Umsetzung", item["yearOfImplementation"]}
      ]
      |> Enum.reject(fn {_label, value} -> blank?(value) end)
      |> Enum.map(fn {label, value} -> "#{label}: #{value}" end)

    [clean(item["description"]), Enum.join(types ++ facts, "\n")]
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n\n")
    |> case do
      "" -> nil
      description -> description
    end
  end

  defp clean(nil), do: nil

  defp clean(value) when is_binary(value),
    do: value |> String.replace("\u00AD", "") |> String.trim()

  defp clean(value), do: to_string(value)

  # "Rüdigerstr.  79" -> "Rüdigerstr. 79"
  defp clean_line(value) do
    case clean(value) do
      nil -> nil
      text -> String.replace(text, ~r/\s+/u, " ")
    end
  end

  defp blank?(value), do: value in [nil, ""]

  defp quarter_start(nil), do: nil

  defp quarter_start({year, quarter}) do
    {month, day} =
      case quarter do
        "1" -> {1, 1}
        "2" -> {4, 1}
        "3" -> {7, 1}
        "4" -> {10, 1}
      end

    DateTime.new!(Date.new!(year, month, day), ~T[00:00:00], "Europe/Berlin")
  end

  defp quarter_end(nil), do: nil

  defp quarter_end({year, quarter}) do
    {month, day} =
      case quarter do
        "1" -> {3, 31}
        "2" -> {6, 30}
        "3" -> {9, 30}
        "4" -> {12, 31}
      end

    DateTime.new!(Date.new!(year, month, day), ~T[00:00:00], "Europe/Berlin")
  end

  defp parse_quarter(nil) do
    nil
  end

  defp parse_quarter(quarter_str) do
    case Regex.named_captures(~r/(?<quarter>[1-4])\. Quartal (?<year>\d{4})/, quarter_str) do
      %{"year" => year, "quarter" => quarter} -> {String.to_integer(year), quarter}
      _ -> nil
    end
  end
end
