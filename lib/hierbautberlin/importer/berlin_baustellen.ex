defmodule Hierbautberlin.Importer.BerlinBaustellen do
  @moduledoc """
  Imports construction sites and other plannable events (street festivals,
  marathons, ...) on public streets from the layer "Planbare Ereignisse im
  öffentlichen Straßenland" of the Berlin geodata infrastructure (see
  `Hierbautberlin.Importer.GdiWfs`).

  The layer has about 8,000 entries, nearly all of them are rated 1 (`bewertung`,
  1 to 5: how much the traffic is affected), e.g. a no parking zone for a
  scaffolding. Only entries rated 2 and above are imported (about 250).

  There is no page per entry, the items have no url. `importid` is a running
  number of the export and probably not stable, the external id is built from the
  street, the section, the start date and the kind of event instead.
  """

  alias Hierbautberlin.GeoData
  alias Hierbautberlin.Importer.GdiWfs

  @min_rating 2
  # Construction sites that go on "forever" end on 31.12.2099
  @last_year 2090

  def import(http_connection \\ Hierbautberlin.HTTPClient) do
    {:ok, source} =
      GeoData.upsert_source(%{
        short_name: "BERLIN_BAUSTELLEN",
        name: "Baustellen und Sperrungen im Straßenland",
        url: GdiWfs.metadata_url("c7e11189-701b-466f-b14f-73de47d03ac5"),
        copyright: "Geoportal Berlin / Planbare Ereignisse im öffentlichen Straßenland"
      })

    result =
      http_connection
      |> GdiWfs.fetch_features("planb_ereignisse", "ereignisse")
      |> Enum.filter(&((&1["properties"]["bewertung"] || 0) >= @min_rating))
      |> Enum.map(&to_geo_item/1)
      |> Enum.uniq_by(& &1.external_id)
      |> Enum.map(fn attrs ->
        {:ok, geo_item} =
          GeoData.upsert_geo_item(Map.merge(attrs, %{source_id: source.id, hidden: false}))

        geo_item
      end)

    GeoData.hide_missing_geo_items(source, Enum.map(result, & &1.external_id))

    {:ok, result}
  rescue
    error ->
      Bugsnag.report(error)
      {:error, error}
  end

  @doc false
  def to_geo_item(feature) do
    properties = feature["properties"]
    date_start = parse_date(properties["dat_beginn"])
    date_end = parse_date(properties["dat_ende"])

    %{
      external_id: external_id(properties),
      title: location(properties),
      subtitle: subtitle(properties),
      description: description(properties, date_start, date_end),
      state: state(properties, date_start, date_end),
      date_start: date_start,
      date_end: date_end,
      geometry: GdiWfs.geometry(feature),
      importance: if(properties["bewertung"] >= 3, do: 1.5, else: 1.0),
      # a closed street matters while it is closed, not months later
      relevance_half_life: 14
    }
  end

  defp external_id(properties) do
    key =
      ~w(strasse von_hausnr bis_hausnr von_str bis_str dat_beginn ereignis)
      |> Enum.map_join("|", &to_string(properties[&1]))

    hash = :crypto.hash(:sha256, key) |> Base.encode16(case: :lower) |> binary_part(0, 16)
    "planb:#{hash}"
  end

  # "Badstraße 48–52", "Landsberger Allee zwischen Vulkanstraße und Storkower
  # Straße", "Genter Straße / Ostender Straße"
  defp location(properties) do
    street =
      [clean(properties["strasse"]), house_numbers(properties)]
      |> Enum.reject(&blank?/1)
      |> Enum.join(" ")

    case {clean(properties["von_str"]), clean(properties["bis_str"])} do
      {from, to} when is_binary(from) and is_binary(to) -> "#{street} zwischen #{from} und #{to}"
      {from, nil} when is_binary(from) -> "#{street} / #{from}"
      {nil, to} when is_binary(to) -> "#{street} / #{to}"
      _ -> street
    end
  end

  defp house_numbers(properties) do
    case {clean(properties["von_hausnr"]), clean(properties["bis_hausnr"])} do
      {nil, _to} -> nil
      {from, nil} -> from
      {from, from} -> from
      {from, to} -> "#{from}–#{to}"
    end
  end

  # "Baustelle: Fahrstreifen-Reduzierung"
  defp subtitle(properties) do
    case restriction(properties) do
      nil -> kind(properties)
      restriction -> "#{kind(properties)}: #{restriction}"
    end
  end

  defp kind(%{"ereignis" => "Arbeitsstelle"}), do: "Baustelle"
  defp kind(_properties), do: "Sonstiges Ereignis"

  # "Sicherung gemäß Vz.-plan" (signs as in the traffic sign plan) says nothing
  defp restriction(properties) do
    case clean(properties["einschr"]) do
      "Sicherung gemäß Vz.-plan" -> nil
      restriction -> restriction
    end
  end

  defp description(properties, date_start, date_end) do
    district =
      case {clean(properties["ortsteil"]), clean(properties["bezirk"])} do
        {nil, district} -> district
        {part, part} -> part
        {part, nil} -> part
        {part, district} -> "#{part} (#{district})"
      end

    [
      {"Ortsteil", district},
      {"Einschränkung",
       properties["einschr"] |> clean() |> replace("Vz.-plan", "Verkehrszeichenplan")},
      {"Zeitraum", period(date_start, date_end)},
      {"Uhrzeit", hours(properties)},
      {"Aufbau ab", clean(properties["aufbau"])},
      {"Abbau bis", clean(properties["abbau"])}
    ]
    |> Enum.reject(fn {_label, value} -> blank?(value) end)
    |> Enum.map_join("\n", fn {label, value} -> "#{label}: #{value}" end)
  end

  defp period(nil, _date_end), do: nil
  defp period(date_start, nil), do: "ab #{format_date(date_start)}"
  defp period(date_start, date_end), do: "#{format_date(date_start)} bis #{format_date(date_end)}"

  # "07:00:00" -> "07:00"
  defp hours(properties) do
    case {clean(properties["uhr_beginn"]), clean(properties["uhr_ende"])} do
      {nil, nil} -> nil
      {from, nil} -> "ab #{String.slice(from, 0, 5)} Uhr"
      {nil, to} -> "bis #{String.slice(to, 0, 5)} Uhr"
      {from, to} -> "#{String.slice(from, 0, 5)} bis #{String.slice(to, 0, 5)} Uhr"
    end
  end

  defp state(properties, date_start, date_end) do
    now = DateTime.utc_now()

    cond do
      date_end && DateTime.before?(date_end, now) -> "finished"
      date_start && DateTime.after?(date_start, now) -> "in_preparation"
      properties["ereignis"] == "Arbeitsstelle" -> "under_construction"
      true -> "active"
    end
  end

  # "21.02.2022", midnight in Berlin
  defp parse_date(text) do
    with text when is_binary(text) <- text,
         [_, day, month, year] <- Regex.run(~r/^(\d{2})\.(\d{2})\.(\d{4})$/, String.trim(text)),
         year = String.to_integer(year),
         true <- year < @last_year,
         {:ok, date} <- Date.new(year, String.to_integer(month), String.to_integer(day)) do
      DateTime.new!(date, ~T[00:00:00], "Europe/Berlin")
    else
      _ -> nil
    end
  end

  defp format_date(datetime), do: Calendar.strftime(datetime, "%d.%m.%Y")

  defp replace(nil, _pattern, _replacement), do: nil
  defp replace(text, pattern, replacement), do: String.replace(text, pattern, replacement)

  defp clean(nil), do: nil

  defp clean(value) do
    case value |> to_string() |> String.trim() do
      "" -> nil
      text -> String.replace(text, ~r/\s+/u, " ")
    end
  end

  defp blank?(value), do: value in [nil, ""]
end
