defmodule Hierbautberlin.Importer.Neubaukompass do
  @moduledoc """
  Imports new residential buildings from Neubaukompass
  (https://www.neubaukompass.de/neubau-immobilien/berlin-region/), a portal where
  developers advertise their projects. The data comes from ImmobilienScout24.

  The region page only lists apartments for sale, so the four listings (apartments
  and houses, to buy and to rent) are read. Each listing page contains its
  projects as JSON in the `data-live-props-value` attribute of a Symfony live
  component, 20 per page (`?pagenumber=N`). A project can appear in more than one
  listing.

  The region "Berlin" includes towns in Brandenburg (Potsdam, Oranienburg,
  Kleinmachnow, ...), only projects with a Berlin postcode are imported.

  ## Coordinates

  The listing has the coordinates of the advertised unit. When the developer hides
  the address (about a sixth of the projects) they are missing, then the project
  page has them (`ApartmentComplex` in its JSON-LD, the postcode area or the
  street when there is no house number). The project page is only read for
  projects that are not stored with a point yet.

  ## Dates

  `readyAt` is free text: "Q4 2028", "Dezember 2027", "01.09.2026", "Herbst 2026",
  "vsl. Mitte 2027", "sofort", "Auf Anfrage", ... It becomes the end of the
  construction (`date_end`, the end of the month, quarter or year). "sofort"
  means the building is finished.
  """
  require Logger

  alias Hierbautberlin.GeoData
  alias Hierbautberlin.Services.GermanMonths

  @base_url "https://www.neubaukompass.de"
  @listings ~w(wohnung-kaufen haus-kaufen wohnung-mieten haus-mieten)
  @headers ["User-Agent": "hierbautberlin.de"]
  @max_pages 50

  @seasons %{"frühjahr" => 5, "frühling" => 5, "sommer" => 8, "herbst" => 11, "winter" => 12}

  def import(http_connection \\ Hierbautberlin.HTTPClient, opts \\ []) do
    delay = Keyword.get(opts, :delay, 1_000)

    {:ok, source} =
      GeoData.upsert_source(%{
        short_name: "NEUBAUKOMPASS",
        name: "Neubaukompass",
        url: "#{@base_url}/neubau-immobilien/berlin-region/",
        copyright: "Neubaukompass / ImmobilienScout24",
        color: "#FFB74D",
        background_color: "#F57C00"
      })

    result =
      @listings
      |> Enum.flat_map(&fetch_listing(http_connection, &1, delay))
      |> Enum.uniq_by(& &1.external_id)
      |> Enum.filter(&berlin?/1)
      |> Enum.map(&add_missing_point(&1, http_connection, source, delay))
      |> Enum.map(fn attrs ->
        {:ok, geo_item} =
          GeoData.upsert_geo_item(
            attrs
            |> Map.drop([:postcode])
            |> Map.merge(%{source_id: source.id, hidden: false})
          )

        geo_item
      end)

    GeoData.hide_missing_geo_items(source, Enum.map(result, & &1.external_id))

    {:ok, result}
  rescue
    error ->
      Bugsnag.report(error)
      {:error, error}
  end

  @doc """
  The projects of a listing page and the number of pages of the listing.
  """
  def parse_listing(html) do
    document = Floki.parse_document!(html)

    props =
      document
      |> Floki.attribute("[data-live-props-value]", "data-live-props-value")
      |> Enum.map(&Jason.decode!/1)
      |> Enum.find(&Map.has_key?(&1, "projects"))

    if props do
      urls = project_urls(document)

      projects =
        props["projects"]
        |> Enum.reject(&(&1["deleted"] == true))
        |> Enum.map(&to_attrs(&1, urls))
        |> Enum.reject(&is_nil/1)

      {projects, props["numberOfPages"] || 1}
    else
      {[], 0}
    end
  end

  @doc """
  The coordinates of the project from the JSON-LD of its project page.
  """
  def parse_project_page(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find(~s(script[type="application/ld+json"]))
    |> Enum.flat_map(fn script ->
      case Jason.decode(Floki.children(script) |> Enum.join()) do
        {:ok, %{"@graph" => graph}} -> graph
        {:ok, %{} = entry} -> [entry]
        _ -> []
      end
    end)
    |> Enum.find_value(fn
      %{"geo" => %{"latitude" => lat, "longitude" => lng}} -> point(lat, lng)
      _ -> nil
    end)
  end

  @doc """
  The end of the construction from the free text of `readyAt`, see the moduledoc.
  """
  def parse_ready_at(nil), do: nil

  def parse_ready_at(text) do
    text = String.downcase(text)

    # "Q'4 2025 / Q'1 2026": the later date counts
    case Regex.scan(~r/20\d\d/, text) do
      [] ->
        nil

      years ->
        year = years |> List.last() |> hd() |> String.to_integer()
        text = text |> String.split(~r/\s\/\s/) |> List.last()
        month = ready_month(text) || 12
        end_of_month(year, month)
    end
  end

  def finished?(nil), do: false

  def finished?(text) do
    Regex.match?(~r/sofort|kurzfristig/iu, text)
  end

  defp ready_month(text) do
    cond do
      match = Regex.run(~r/\b\d{1,2}\.(\d{1,2})\.20\d\d/, text) ->
        match |> Enum.at(1) |> String.to_integer()

      match = Regex.run(~r/\b(\d{1,2})\/20\d\d/, text) ->
        match |> Enum.at(1) |> String.to_integer()

      # "Q2/Q3 2027": the later quarter counts
      quarters = Regex.scan(~r/q'?\s?([1-4])|([1-4])\.\s?quartal/, text) |> presence() ->
        quarter = quarters |> List.last() |> Enum.drop(1) |> Enum.reject(&(&1 == "")) |> hd()
        String.to_integer(quarter) * 3

      match = Regex.run(~r/#{GermanMonths.pattern()}/iu, text) ->
        GermanMonths.number(hd(match))

      season = Enum.find(@seasons, fn {name, _month} -> String.contains?(text, name) end) ->
        elem(season, 1)

      String.contains?(text, "mitte") ->
        6

      true ->
        nil
    end
    |> then(&if(&1 in 1..12, do: &1, else: nil))
  end

  defp end_of_month(year, month) do
    date = Date.new!(year, month, 1) |> Date.end_of_month()
    DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
  end

  defp to_attrs(%{"projectId" => id} = project, urls) when is_integer(id) do
    details = project["project"] || %{}
    real_estate = project["resultlist.realEstate"] || %{}
    address = real_estate["address"] || %{}
    ready_at = details["readyAt"]

    %{
      external_id: to_string(id),
      title: clean(project["name"] || details["name"]),
      subtitle: clean(project["cardSubTitle"]),
      description: description(project, ready_at),
      url: Map.get(urls, id, "#{@base_url}/neubau/projekt/#{id}.html"),
      state: state(ready_at),
      date_end: parse_ready_at(ready_at),
      date_updated: parse_datetime(project["@modification"]),
      # relevant from the day it is advertised until it is finished, `date_start`
      # would be shown as the start of the construction
      relevant_from: parse_datetime(project["@creation"]),
      relevant_until: parse_ready_at(ready_at),
      geo_point: unit_point(project["unit"]) || coordinate_point(address["wgs84Coordinate"]),
      postcode: address["postcode"] || postcode(project["cardDescription"])
    }
    |> then(&if(&1.title in [nil, ""], do: nil, else: &1))
  end

  defp to_attrs(_project, _urls), do: nil

  defp state(ready_at) do
    ready = parse_ready_at(ready_at)

    if finished?(ready_at) or (ready && DateTime.before?(ready, DateTime.utc_now())) do
      "finished"
    else
      "under_construction"
    end
  end

  defp unit_point(%{"latitude" => lat, "longitude" => lng}), do: point(lat, lng)
  defp unit_point(_unit), do: nil

  defp coordinate_point(%{"latitude" => lat, "longitude" => lng}), do: point(lat, lng)
  defp coordinate_point(_coordinate), do: nil

  defp point(lat, lng) when is_number(lat) and is_number(lng) do
    %Geo.Point{coordinates: {lng / 1, lat / 1}, srid: 4326}
  end

  defp point(_lat, _lng), do: nil

  # "Neubau von 12 Eigentumswohnungen. Herbartstraße 23, 14057 Berlin. 2 - 4
  # Zimmer, 12 Wohneinheiten in Berlin - Charlottenburg (Charlottenburg). Preis:
  # ... Fertigstellung: Q4 2028"
  defp description(project, ready_at) do
    details = project["project"] || %{}
    price = details["price"]

    [
      project["cardTeaser"],
      project["cardDescription"],
      project["feedDescription"],
      if(present?(price), do: "#{price_label(project)}: #{price}"),
      if(present?(ready_at), do: "Fertigstellung: #{ready_at}")
    ]
    |> Enum.map(&clean/1)
    |> Enum.filter(&present?/1)
    |> Enum.uniq()
    |> Enum.join("\n")
  end

  defp price_label(%{"rentRealEstates" => true}), do: "Miete"
  defp price_label(_project), do: "Preis"

  # Projects to buy are at /neubau/<slug>/<id>.html, to rent at
  # /neubau-mieten/<slug>/<id>.html
  defp project_urls(document) do
    document
    |> Floki.attribute(~s(a[href^="/neubau"]), "href")
    |> Enum.flat_map(fn href ->
      case Regex.run(~r{^/neubau(?:-mieten)?/[^/]+/(\d+)\.html$}, href) do
        [_, id] -> [{String.to_integer(id), @base_url <> href}]
        _ -> []
      end
    end)
    |> Map.new()
  end

  # Berlin postcodes are 10115 to 14199, the ones around it in Brandenburg start
  # at 14467 (Potsdam)
  defp berlin?(%{postcode: postcode}) do
    case Integer.parse(to_string(postcode)) do
      {number, ""} -> number >= 10_115 and number <= 14_199
      _ -> false
    end
  end

  defp postcode(text) do
    case Regex.run(~r/\b(\d{5})\b/, to_string(text)) do
      [_, postcode] -> postcode
      _ -> nil
    end
  end

  defp add_missing_point(%{geo_point: %Geo.Point{}} = attrs, _http_connection, _source, _delay),
    do: attrs

  defp add_missing_point(attrs, http_connection, source, delay) do
    stored = GeoData.get_geo_item_with_external_id(source.id, attrs.external_id)

    point =
      if stored && stored.geo_point do
        stored.geo_point
      else
        Process.sleep(delay)
        http_connection |> fetch(attrs.url) |> then(&(&1 && parse_project_page(&1)))
      end

    Map.put(attrs, :geo_point, point)
  end

  defp fetch_listing(http_connection, listing, delay, page \\ 1)

  defp fetch_listing(_http_connection, _listing, _delay, page) when page > @max_pages, do: []

  defp fetch_listing(http_connection, listing, delay, page) do
    if page > 1, do: Process.sleep(delay)

    url = "#{@base_url}/neubau-immobilien/berlin-region/#{listing}/?pagenumber=#{page}"

    case fetch(http_connection, url) do
      nil ->
        raise "Neubaukompass: could not read #{url}"

      html ->
        {projects, pages} = parse_listing(html)

        if page < pages do
          projects ++ fetch_listing(http_connection, listing, delay, page + 1)
        else
          projects
        end
    end
  end

  defp fetch(http_connection, url) do
    response = http_connection.get!(url, @headers, timeout: 60_000, recv_timeout: 60_000)

    if response.status_code != 200 do
      Logger.warning("Neubaukompass returned #{response.status_code} for #{url}")
      nil
    else
      response.body
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(text) do
    case DateTime.from_iso8601(text) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      _ -> nil
    end
  end

  defp clean(nil), do: nil

  defp clean(text) do
    text
    |> to_string()
    |> String.replace(" ", " ")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp presence([]), do: nil
  defp presence(list), do: list

  defp present?(text), do: is_binary(text) and String.trim(text) != ""
end
