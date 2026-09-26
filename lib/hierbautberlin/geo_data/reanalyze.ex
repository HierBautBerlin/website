defmodule Hierbautberlin.GeoData.Reanalyze do
  @moduledoc """
  Runs the address matching again for existing news items, e.g. after the
  matching or the street data was improved.

  News items imported since 2026-09 store the analyzed text. For older ones the
  text is extracted again:

    * Amtsblatt: from the PDFs in the file storage (their outline is rebuilt
      from the news items, the stored PDFs don't have one anymore)
    * press releases: the article pages are fetched again (slowly, berlin.de
      throttles fast clients)

  By default nothing is changed (`dry_run: true`), only statistics are returned.
  Otherwise the links are updated and the extracted texts are stored.
  """
  require Logger

  import Ecto.Query, warn: false

  alias Hierbautberlin.FileStorage
  alias Hierbautberlin.GeoData
  alias Hierbautberlin.GeoData.{NewsItem, Source}
  alias Hierbautberlin.Importer.{BerlinerAmtsblatt, BerlinPresse}
  alias Hierbautberlin.Repo
  alias Hierbautberlin.Services.Berlin

  @sources ~w(BERLIN_AMTSBLATT BERLIN_PRESSE GRUEN_BERLIN)

  def sources, do: @sources

  @doc """
  Options:
    * `:source` - one of `sources/0` (required)
    * `:since` - only news items published since this `DateTime`
    * `:dry_run` - don't change anything (default `true`)
    * `:http_connection` - HTTP client for press releases
    * `:delay` - milliseconds between press release requests (default 1000)
  """
  def run(opts) do
    source = Repo.get_by!(Source, short_name: Keyword.fetch!(opts, :source))
    dry_run = Keyword.get(opts, :dry_run, true)

    {stored, without_text} =
      source
      |> news_items(Keyword.get(opts, :since))
      |> Enum.split_with(& &1.full_text)

    stored
    |> Enum.map(&{&1, {&1.full_text, &1.districts || []}})
    |> Stream.concat(texts_for(without_text, source.short_name, opts))
    |> Enum.reduce(%{items: 0, changed: 0, added: 0, removed: 0, missing_text: 0}, fn
      {_news_item, nil}, stats ->
        %{stats | items: stats.items + 1, missing_text: stats.missing_text + 1}

      {news_item, {text, districts}}, stats ->
        {added, removed} = reanalyze(news_item, text, districts, dry_run)

        %{
          stats
          | items: stats.items + 1,
            changed: stats.changed + if(added + removed > 0, do: 1, else: 0),
            added: stats.added + added,
            removed: stats.removed + removed
        }
    end)
  end

  defp news_items(source, since) do
    query = from n in NewsItem, where: n.source_id == ^source.id, order_by: n.id
    query = if since, do: where(query, [n], n.published_at >= ^since), else: query

    query
    |> Repo.all()
    |> Repo.preload([:geo_streets, :geo_street_numbers, :geo_places])
  end

  defp texts_for(news_items, "BERLIN_AMTSBLATT", _opts) do
    news_items
    |> Enum.group_by(&pdf_name/1)
    |> Enum.flat_map(fn {pdf_name, items} ->
      texts = extract_amtsblatt(pdf_name, items)
      Enum.map(items, &{&1, Map.get(texts, &1.id)})
    end)
  end

  defp texts_for(news_items, "BERLIN_PRESSE", opts) do
    http_connection = Keyword.get(opts, :http_connection, Hierbautberlin.HTTPClient)
    delay = Keyword.get(opts, :delay, 1_000)

    Stream.map(news_items, fn news_item ->
      Process.sleep(delay)
      article = BerlinPresse.fetch_text_from_html(news_item.url, http_connection)
      text = Enum.join([news_item.title, news_item.content, article], "\n")
      {news_item, {text, districts_from_url(news_item.url)}}
    end)
  end

  # Grün Berlin releases always store their text, they are never without one
  defp texts_for(news_items, _source, _opts) do
    Enum.map(news_items, &{&1, nil})
  end

  defp pdf_name(news_item) do
    case Regex.run(~r{^/view_pdf/amtsblatt/([^?]+)}, news_item.external_id || "") do
      [_, name] -> name
      _ -> nil
    end
  end

  defp page_number(news_item) do
    case Regex.run(~r{[?&]page=(\d+)}, news_item.external_id || "") do
      [_, page] -> String.to_integer(page)
      _ -> nil
    end
  end

  # Returns a map of news item id => {text, districts}
  defp extract_amtsblatt(nil, _news_items), do: %{}

  defp extract_amtsblatt(pdf_name, news_items) do
    path = FileStorage.path_for_file("amtsblatt/#{pdf_name}")

    if File.exists?(path) do
      do_extract_amtsblatt(path, news_items)
    else
      Logger.warning("Amtsblatt #{pdf_name} is not in the file storage")
      %{}
    end
  rescue
    error ->
      Logger.warning("Could not extract Amtsblatt #{pdf_name}: #{Exception.message(error)}")
      %{}
  end

  defp do_extract_amtsblatt(path, news_items) do
    case BerlinerAmtsblatt.extract_items(path) do
      [] -> extract_along_news_items(path, news_items)
      items -> texts_by_id(news_items, Map.new(items, &{&1.url, &1}), & &1.external_id)
    end
  end

  # The stored PDFs were shortened with qpdf, which drops the outline. The
  # headings of the notices are the titles of the news items, so the text can
  # be split along them. The section is unknown, the district is taken from
  # the text.
  defp extract_along_news_items(path, news_items) do
    structure =
      news_items
      |> Enum.filter(&page_number/1)
      |> Enum.sort_by(&{page_number(&1), &1.id})
      |> Enum.map(&%{title: &1.title, page_number: page_number(&1), news_item_id: &1.id})

    path
    |> BerlinerAmtsblatt.extract_items_with_structure(
      structure,
      BerlinerAmtsblatt.get_number_of_pages(path)
    )
    |> Map.new(fn item ->
      text = BerlinerAmtsblatt.cut_at_skipped_section(item.full_text)
      {item.structure_item.news_item_id, {text, districts_from_text(text)}}
    end)
  end

  # "Das Bezirksamt Pankow von Berlin erlässt …" -> ["Pankow"]
  defp districts_from_text(text) do
    ~r/Bezirksamt(?:es|s)?\s+([\p{L}-]+)\s+von\s+Berlin/u
    |> Regex.scan(text, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.filter(&(&1 in Berlin.districts()))
  end

  defp texts_by_id(news_items, extracted, key) do
    Enum.reduce(news_items, %{}, fn news_item, texts ->
      case Map.get(extracted, key.(news_item)) do
        nil -> texts
        item -> Map.put(texts, news_item.id, {item.full_text, [item.section]})
      end
    end)
  end

  # "https://www.berlin.de/ba-friedrichshain-kreuzberg/…" -> ["Friedrichshain-Kreuzberg"]
  defp districts_from_url(url) do
    case Regex.run(~r{berlin\.de/ba-([a-z-]+)/}, url || "") do
      [_, slug] ->
        Enum.filter(Berlin.districts(), fn district ->
          slug == district |> String.downcase() |> String.replace(["ö", "ä", "ü"], &umlaut/1)
        end)

      _ ->
        []
    end
  end

  defp umlaut("ö"), do: "oe"
  defp umlaut("ä"), do: "ae"
  defp umlaut("ü"), do: "ue"

  defp reanalyze(news_item, text, districts, dry_run) do
    result = GeoData.analyze_text(text, %{districts: districts})

    before = link_keys(news_item.geo_streets, news_item.geo_street_numbers, news_item.geo_places)

    after_analysis =
      link_keys(
        result.streets ++ result.context_streets,
        result.street_numbers ++ result.interpolated,
        result.places
      )

    added = MapSet.size(MapSet.difference(after_analysis, before))
    removed = MapSet.size(MapSet.difference(before, after_analysis))

    # the extracted text is stored, so the next run doesn't need to extract it again
    if not dry_run and (added + removed > 0 or is_nil(news_item.full_text)) do
      news_item
      |> NewsItem.change_associations(
        geo_streets: result.streets,
        geo_street_numbers: GeoData.store_interpolated_numbers(result),
        context_streets: result.context_streets,
        geo_places: result.places
      )
      |> Ecto.Changeset.change(full_text: text, districts: districts)
      |> Repo.update!()
    end

    {added, removed}
  end

  defp link_keys(streets, street_numbers, places) do
    Enum.map(streets, &{:street, &1.id})
    |> Enum.concat(Enum.map(street_numbers, &street_number_key/1))
    |> Enum.concat(Enum.map(places, &{:place, &1.id}))
    |> MapSet.new()
  end

  defp street_number_key(%{id: id}) when not is_nil(id), do: {:street_number, id}

  # A number that was only interpolated has no id yet: it is stored when the
  # item is written, and found by the normal lookup from the next run on.
  defp street_number_key(number),
    do: {:interpolated, number.geo_street_id, number.number}
end
