defmodule Hierbautberlin.Importer.StepWohnen do
  @moduledoc """
  Imports the larger housing sites and the new urban districts ("Neue
  Stadtquartiere") of the urban development plan for housing (Stadtentwicklungsplan
  Wohnen 2040, adopted in September 2024) from the service `step_wo_2040` of the
  Berlin geodata infrastructure (see `Hierbautberlin.Importer.GdiWfs`).

    * `h_step_wo_2040_wobau_fertig`: sites for 200 and more flats (points) with
      the completion horizon: under construction, short term (until 2026),
      medium term (2027 to 2031) or long term (2032 to 2040).
    * `i_step_wo_2040_wobau_gemeinw`: the same sites, whether they are meant for
      public-interest housing (e.g. the state-owned housing companies).
    * `j_step_wo_2040_neustadtquar`: the 24 new urban districts with the
      targeted start of the construction. The areas are no outlines, every
      district is the same circle (about 1.8 km wide) around its location, so
      the district is a point: the one of its housing site, otherwise the center
      of the circle.

  Most new urban districts are a housing site, too (same name). They are imported
  once, as district with the number of flats and the completion of the site.

  The plan has no page per site. Some new urban districts have one on berlin.de.
  """

  alias Hierbautberlin.GeoData
  alias Hierbautberlin.Importer.GdiWfs

  @service "step_wo_2040"
  @step_url "https://www.berlin.de/sen/stadtentwicklung/planung/stadtentwicklungsplaene/step-wohnen-2040/"
  @districts_url "https://www.berlin.de/sen/stadtentwicklung/neue-stadtquartiere/"

  # by `gisid`
  @district_pages %{
    "S01" => "blankenburger-sueden",
    "S02" => "buch-am-sandhaus",
    "S03" => "buckower-felder",
    "S05" => "wasserstadt-berlin-oberhavel",
    "S06" => "das-neue-gartenfeld",
    "S07" => "johannisthal-adlershof",
    "S08" => "ehemaliger-gueterbahnhof-koepenick",
    "S17" => "elisabeth-aue",
    "S18" => "georg-knorr-park-teilgebiet-ost",
    "S19" => "spaethsfelde",
    "S21" => "karow-sued"
  }

  # {first year, last year} of a horizon of the plan, "bis 2026" includes the
  # projects under construction
  @horizons [
    {~r/^bis 2026|kurzfristig|^im bau/iu, {2022, 2026}},
    {~r/^2027/u, {2027, 2031}},
    {~r/^2032/u, {2032, 2040}},
    {~r/mittelfristig/iu, {2027, 2031}},
    {~r/langfristig/iu, {2032, 2040}}
  ]

  def import(http_connection \\ Hierbautberlin.HTTPClient) do
    {:ok, source} =
      GeoData.upsert_source(%{
        short_name: "STEP_WOHNEN",
        name: "Stadtentwicklungsplan Wohnen 2040",
        url: @step_url,
        copyright: "Geoportal Berlin / Stadtentwicklungsplan (StEP) Wohnen 2040"
      })

    sites = fetch_sites(http_connection)
    districts = GdiWfs.fetch_features(http_connection, @service, "j_step_wo_2040_neustadtquar")
    district_names = MapSet.new(districts, &clean(&1["properties"]["bez"]))
    sites_by_name = Map.new(sites, &{&1.name, &1})

    items =
      Enum.map(districts, &district_to_geo_item(&1, sites_by_name)) ++
        (sites
         |> Enum.reject(&MapSet.member?(district_names, &1.name))
         |> Enum.map(&site_to_geo_item/1))

    result =
      items
      |> Enum.reject(&is_nil/1)
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

  # The housing sites with the completion horizon and the public-interest flag
  defp fetch_sites(http_connection) do
    public_interest =
      http_connection
      |> GdiWfs.fetch_features(@service, "i_step_wo_2040_wobau_gemeinw")
      |> Map.new(&{&1["properties"]["gisid"], clean(&1["properties"]["leg_gemeinw"])})

    http_connection
    |> GdiWfs.fetch_features(@service, "h_step_wo_2040_wobau_fertig")
    |> Enum.map(fn feature ->
      properties = feature["properties"]

      %{
        id: properties["gisid"],
        name: clean(properties["bez"]),
        flats: clean(properties["we_kat"]),
        completion: clean(properties["leg_fertig"]),
        public_interest: public_interest[properties["gisid"]],
        geometry: GdiWfs.geometry(feature)
      }
    end)
    |> Enum.reject(&(is_nil(&1.id) or is_nil(&1.name)))
  end

  defp site_to_geo_item(site) do
    under_construction? = site.completion == "Im Bau"
    {from, until} = horizon(site.completion)

    %{
      external_id: "site:#{site.id}",
      title: site.name,
      subtitle: Enum.join(["Wohnungsbau" | List.wrap(site.flats)], ", "),
      description:
        facts([
          {"Wohneinheiten", site.flats},
          {"Fertigstellung", site_completion(site.completion)},
          {"Gemeinwohlorientierung", site.public_interest}
        ]),
      url: nil,
      state: if(under_construction?, do: "under_construction", else: "intended"),
      geo_point: site.geometry,
      relevant_from: from,
      relevant_until: until,
      importance: if(under_construction?, do: 1.5, else: 1.0)
    }
  end

  defp district_to_geo_item(feature, sites_by_name) do
    properties = feature["properties"]
    id = properties["gisid"]
    name = clean(properties["bez"])
    start = clean(properties["kat"])
    site = Map.get(sites_by_name, name)

    if id && name do
      {from, until} = horizon(start)

      %{
        external_id: "district:#{id}",
        title: name,
        subtitle: "Neues Stadtquartier",
        description:
          facts([
            {"Angestrebter Baubeginn", district_start(start)},
            {"Wohneinheiten", site && site.flats},
            {"Fertigstellung", site && site_completion(site.completion)},
            {"Gemeinwohlorientierung", site && site.public_interest}
          ]),
        url: district_url(id),
        state: district_state(start),
        geo_point: (site && site.geometry) || center(GdiWfs.geometry(feature)),
        geometry: nil,
        relevant_from: from,
        relevant_until: until,
        importance: 1.5
      }
    end
  end

  # The average of the corners of the circle
  defp center(%Geo.MultiPolygon{coordinates: [[[_ | ring] | _holes] | _polygons]} = shape)
       when ring != [] do
    {lngs, lats} = Enum.unzip(ring)

    %Geo.Point{
      coordinates: {Enum.sum(lngs) / length(lngs), Enum.sum(lats) / length(lats)},
      srid: shape.srid
    }
  end

  defp center(%Geo.Point{} = point), do: point
  defp center(_shape), do: nil

  defp district_url(id) do
    case Map.fetch(@district_pages, id) do
      {:ok, slug} -> "#{@districts_url}#{slug}/"
      :error -> nil
    end
  end

  defp district_state("Im Bau"), do: "under_construction"
  defp district_state("Größtenteils abgeschlossen"), do: "finished"
  defp district_state(_start), do: "in_planning"

  # "Bis 2026" -> "bis 2026", "Im Bau" -> "hat begonnen"
  defp district_start(nil), do: nil
  defp district_start("Im Bau"), do: "hat begonnen (im Bau)"
  defp district_start("Größtenteils abgeschlossen"), do: "hat begonnen (größtenteils fertig)"
  defp district_start(start), do: String.replace(start, ~r/^Bis/u, "bis")

  defp site_completion(nil), do: nil
  defp site_completion("Im Bau"), do: "im Bau"
  defp site_completion("Kurzfristiges Potenzial"), do: "kurzfristig (bis 2026)"
  defp site_completion("Mittelfristiges Potenzial"), do: "mittelfristig (2027 bis 2031)"
  defp site_completion("Langfristiges Potenzial"), do: "langfristig (2032 bis 2040)"
  defp site_completion(completion), do: completion

  defp horizon(nil), do: {nil, nil}

  defp horizon(text) do
    case Enum.find(@horizons, fn {pattern, _years} -> Regex.match?(pattern, text) end) do
      {_pattern, {first, last}} ->
        {DateTime.new!(Date.new!(first, 1, 1), ~T[00:00:00], "Europe/Berlin"),
         DateTime.new!(Date.new!(last, 12, 31), ~T[00:00:00], "Europe/Berlin")}

      nil ->
        {nil, nil}
    end
  end

  defp facts(facts) do
    [
      "Aus dem Stadtentwicklungsplan Wohnen 2040."
      | facts
        |> Enum.reject(fn {_label, value} -> value in [nil, ""] end)
        |> Enum.map(fn {label, value} -> "#{label}: #{value}" end)
    ]
    |> Enum.join("\n")
  end

  defp clean(nil), do: nil

  defp clean(value) do
    case value |> to_string() |> String.trim() do
      "" -> nil
      text -> String.replace(text, ~r/\s+/u, " ")
    end
  end
end
