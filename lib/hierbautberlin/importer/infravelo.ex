defmodule Hierbautberlin.Importer.Infravelo do
  alias Hierbautberlin.Importer.KmlParser
  alias Hierbautberlin.Importer.LiqdApi
  alias Hierbautberlin.GeoData
  alias Hierbautberlin.Services.Quarters

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
      |> Enum.map(&Quarters.parse(&1["date"]))
      |> Enum.reject(&is_nil/1)

    cond do
      Quarters.parse(item["dateStart"]) || Quarters.parse(item["dateEnd"]) ->
        {Quarters.first_day(Quarters.parse(item["dateStart"])),
         Quarters.last_day(Quarters.parse(item["dateEnd"]))}

      is_integer(item["yearOfImplementation"]) ->
        year = item["yearOfImplementation"]
        {Quarters.first_day({year, 1}), Quarters.last_day({year, 4})}

      milestone_quarters != [] ->
        {Quarters.first_day(Enum.min(milestone_quarters)),
         Quarters.last_day(Enum.max(milestone_quarters))}

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
end
