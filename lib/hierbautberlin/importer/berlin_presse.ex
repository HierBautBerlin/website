defmodule Hierbautberlin.Importer.BerlinPresse do
  @moduledoc """
  Imports the press releases of the Berlin press portal (berlin.de/presse): the
  feed lists title, teaser and department, the text comes from the article page.

  The text is stored with the news item (`full_text`), so the address matching
  can run again without fetching it (`Hierbautberlin.GeoData.Reanalyze`). When
  the article page could not be read, only title and teaser are analyzed and no
  text is stored: the next import fetches the article again.
  """
  require Logger

  import Ecto.Query, warn: false

  alias Hierbautberlin.GeoData
  alias Hierbautberlin.GeoData.NewsItem
  alias Hierbautberlin.Repo
  alias Hierbautberlin.Services.Berlin

  @feed_url "https://www.berlin.de/presse/pressemitteilungen/index/feed?institutions%5B%5D=Presse-+und+Informationsamt+des+Landes+Berlin&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Arbeit%2C+Soziales%2C+Gleichstellung%2C+Integration%2C+Vielfalt+und+Antidiskriminierung&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Bildung%2C+Jugend+und+Familie&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Finanzen&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Inneres+und+Sport&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Justiz+und+Verbraucherschutz&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Kultur+und+Gesellschaftlichen+Zusammenhalt&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Mobilit%C3%A4t%2C+Verkehr%2C+Klimaschutz+und+Umwelt&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Stadtentwicklung%2C+Bauen+und+Wohnen&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Wirtschaft%2C+Energie+und+Betriebe&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Wissenschaft%2C+Gesundheit+und+Pflege&institutions%5B%5D=Landesdenkmalamt&institutions%5B%5D=Bezirksamt+Charlottenburg-Wilmersdorf&institutions%5B%5D=Bezirksamt+Friedrichshain-Kreuzberg&institutions%5B%5D=Bezirksamt+Lichtenberg&institutions%5B%5D=Bezirksamt+Marzahn-Hellersdorf&institutions%5B%5D=Bezirksamt+Mitte&institutions%5B%5D=Bezirksamt+Neuk%C3%B6lln&institutions%5B%5D=Bezirksamt+Pankow&institutions%5B%5D=Bezirksamt+Reinickendorf&institutions%5B%5D=Bezirksamt+Spandau&institutions%5B%5D=Bezirksamt+Steglitz-Zehlendorf&institutions%5B%5D=Bezirksamt+Tempelhof-Sch%C3%B6neberg&institutions%5B%5D=Bezirksamt+Treptow-K%C3%B6penick"

  # The departments whose releases were missing between 2022 and 2026 because
  # the feed above still used their old names. The feed reaches back to 2022.
  @archive_feed_url "https://www.berlin.de/presse/pressemitteilungen/index/feed?institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Mobilit%C3%A4t%2C+Verkehr%2C+Klimaschutz+und+Umwelt&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Stadtentwicklung%2C+Bauen+und+Wohnen&institutions%5B%5D=Landesdenkmalamt"

  # How many feed pages (10 releases each) a normal import reads. On busy days
  # more than 10 releases are published within an hour, and an import can fail.
  @pages 3

  @doc """
  Imports the press releases of the newest feed pages.

  Options:
    * `:pages` - how many feed pages to read (default #{@pages}, 10 releases each)
    * `:skip_imported` - don't fetch the article pages of releases that are
      already stored with their text, so a normal run mostly reads the feed
      (default `true`)
  """
  def import(http_connection \\ Hierbautberlin.HTTPClient.Slow, opts \\ []) do
    source = upsert_source()

    items =
      http_connection
      |> feed_items(@feed_url, Keyword.get(opts, :pages, @pages))
      |> Enum.uniq_by(& &1["link"])

    skip =
      if Keyword.get(opts, :skip_imported, true),
        do: urls_with_text(source, Enum.map(items, & &1["link"])),
        else: MapSet.new()

    result =
      items
      |> Enum.reject(&MapSet.member?(skip, &1["link"]))
      |> Enum.map(&(&1 |> parse_entry(http_connection) |> upsert_entry(source)))

    {:ok, result}
  rescue
    error ->
      Bugsnag.report(error)
      {:error, error}
  end

  @doc """
  Imports the archive of the building and transport departments and the
  Landesdenkmalamt page by page, up to `max_pages` feed pages (10 releases each).
  Releases that are already stored are skipped, so an aborted run can simply be
  started again.
  """
  def import_archive(http_connection \\ Hierbautberlin.HTTPClient.Slow, max_pages \\ 200) do
    source = upsert_source()
    imported = imported_urls(source)

    result =
      http_connection
      |> feed_items(@archive_feed_url, max_pages)
      |> Stream.reject(&MapSet.member?(imported, &1["link"]))
      |> Stream.map(&(&1 |> parse_entry(http_connection) |> upsert_entry(source)))
      |> Enum.to_list()

    {:ok, result}
  end

  @doc """
  Fetches the press releases of the given feed page (newest first) including the
  full text of each release.
  """
  def fetch_entries(http_connection, page \\ 1) do
    case fetch_items(http_connection, @feed_url, page) do
      {:ok, items} -> Enum.map(items, &parse_entry(&1, http_connection))
      {:error, status} -> raise feed_error(status)
    end
  end

  defp upsert_source do
    {:ok, source} =
      GeoData.upsert_source(%{
        short_name: "BERLIN_PRESSE",
        name: "Presseportal des Landes Berlin",
        url: "https://www.berlin.de/presse/",
        copyright: "Stadt Berlin"
      })

    source
  end

  defp upsert_entry(entry, source) do
    news_item =
      GeoData.upsert_news_item!(
        %{
          external_id: entry.url,
          title: entry.title,
          url: entry.url,
          content: entry.content,
          published_at: entry.published_at,
          source_id: source.id
        },
        entry.full_text,
        entry.districts
      )

    # Without the article the text is incomplete. It is not stored, so the next
    # import and the reanalysis fetch the article again.
    if entry.article_fetched,
      do: news_item,
      else: news_item |> Ecto.Changeset.change(full_text: nil) |> Repo.update!()
  end

  defp urls_with_text(source, urls) do
    from(item in NewsItem,
      where: item.source_id == ^source.id and item.external_id in ^urls,
      where: not is_nil(item.full_text),
      select: item.external_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp imported_urls(source) do
    from(item in NewsItem, where: item.source_id == ^source.id, select: item.external_id)
    |> Repo.all()
    |> MapSet.new()
  end

  # The releases of the first `max_pages` feed pages. Pages after the last one
  # return the last page again, so paging stops when a page repeats the previous
  # one. Without the first page there is nothing to import, which is an error.
  # When a later page can't be read, the releases read so far are still imported.
  defp feed_items(http_connection, feed_url, max_pages) do
    {1, nil}
    |> Stream.unfold(fn
      {page, _previous} when page > max_pages -> nil
      {page, previous} -> next_page(http_connection, feed_url, page, previous)
    end)
    |> Stream.concat()
  end

  defp next_page(http_connection, feed_url, page, previous) do
    case fetch_items(http_connection, feed_url, page) do
      {:ok, items} ->
        links = Enum.map(items, & &1["link"])
        if items == [] or links == previous, do: nil, else: {items, {page + 1, links}}

      {:error, status} when page == 1 ->
        raise feed_error(status)

      {:error, status} ->
        Logger.warning("#{feed_error(status)} (page #{page})")
        nil
    end
  end

  defp feed_error(status),
    do: "The feed of the Berlin press portal answered with status #{status}"

  defp fetch_items(http_connection, feed_url, page) do
    url = if page == 1, do: feed_url, else: "#{feed_url}&page=#{page}"

    with {:ok, rss} <- fetch_rss(http_connection, url) do
      {:ok, Map.get(rss, "items", [])}
    end
  end

  defp parse_entry(entry, http_connection) do
    title = HtmlEntities.decode(entry["title"])
    content = HtmlEntities.decode(entry["description"])

    published =
      entry["pub_date"]
      |> Timex.parse!("{RFC1123}")
      |> Timex.Timezone.convert("Etc/UTC")

    districts =
      entry["categories"]
      |> Enum.map(& &1["name"])
      |> Enum.map(&Berlin.find_districts(&1))
      |> List.flatten()

    text = fetch_text_from_html(entry["link"], http_connection)

    %{
      title: title,
      content: content,
      url: entry["link"],
      published_at: published,
      districts: districts,
      full_text: title <> "\n" <> content <> "\n" <> text,
      article_fetched: String.trim(text) != ""
    }
  end

  @doc """
  The text of the article page, `""` when it could not be read. A single broken
  article page must not break the whole import, the title and the teaser are
  still analyzed.
  """
  def fetch_text_from_html(url, http_connection) do
    response =
      http_connection.get!(
        url,
        ["User-Agent": "hierbautberlin.de"],
        timeout: 60_000,
        recv_timeout: 60_000
      )

    if response.status_code != 200 do
      Logger.warning("Could not fetch press release #{url}: status #{response.status_code}")
      ""
    else
      strip_html(response.body)
    end
  rescue
    error ->
      Logger.warning("Could not fetch press release #{url}: #{Exception.message(error)}")
      ""
  end

  def strip_html(text) do
    # keep line breaks between paragraphs, otherwise words of two paragraphs are glued together
    text = String.replace(text, ~r{</(p|li|h\d|div)>|<br\s*/?>}i, "\\0\n")
    {:ok, document} = Floki.parse_document(text)

    # ".article[role='main']" is the layout until 2025
    document
    |> Floki.find(".article[role='main'], #layout-grid__area--maincontent .textile")
    |> Enum.map_join("\n", &Floki.text/1)
    |> String.replace(
      ~r/^\s*(Kontakt(e)?|Ansprechpartner(\*innen)?|Pressekontakt(e)?):.*\z/sm,
      ""
    )
  end

  defp fetch_rss(http_connection, url) do
    response =
      http_connection.get!(
        url,
        ["User-Agent": "hierbautberlin.de"],
        timeout: 60_000,
        recv_timeout: 60_000
      )

    if response.status_code != 200 do
      {:error, response.status_code}
    else
      FastRSS.parse(response.body)
    end
  end
end
