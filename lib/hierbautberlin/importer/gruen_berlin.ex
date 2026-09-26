defmodule Hierbautberlin.Importer.GruenBerlin do
  @moduledoc """
  Imports the press releases of Grün Berlin, the company of the state of Berlin
  that plans and builds many of the parks, squares and bike routes of the city
  (https://gruen-berlin.de/presse/pressemitteilungen).

  The list pages contain title, project and date of every release, the article
  page the text. The list is paginated with a link that carries a cHash, so the
  pages are followed instead of built.

  Releases of infraVelo are skipped, their projects are already imported by
  `Hierbautberlin.Importer.Infravelo`. A few older releases redirect to the
  website of their project, only their title and project are analyzed.

  ## Getting the releases onto the map

  The project a release belongs to ("Tempelhofer Feld", "Mauerpark") is the
  place it is about, so it is analyzed together with the text. These places are
  in the geo data as parks, squares and lakes from OpenStreetMap (see
  `Hierbautberlin.GeoImport.OSM`) - no list of projects is kept here, a new
  project is found as soon as its name or the streets around it are in the text.
  """
  require Logger

  import Ecto.Query, warn: false

  alias Hierbautberlin.GeoData
  alias Hierbautberlin.GeoData.NewsItem
  alias Hierbautberlin.Repo
  alias Hierbautberlin.Services.GermanMonths

  @base_url "https://gruen-berlin.de"
  @list_url "#{@base_url}/presse/pressemitteilungen"
  @headers ["User-Agent": "hierbautberlin.de"]

  # How many list pages (9 releases each) a normal import reads
  @pages 3

  # A shorter text means the article page could not be read, it is read again on
  # the next run
  @short_text 400

  # Their projects are imported from infravelo.de directly
  @skipped_projects ["infraVelo"]

  @doc """
  Imports the press releases of the newest list pages.

  Options:
    * `:pages` - how many list pages to read (default #{@pages}, 9 releases each)
    * `:skip_imported` - don't fetch the article pages of releases that are
      already stored, so a normal run only reads the list pages (default `true`)
  """
  def import(http_connection \\ Hierbautberlin.HTTPClient, opts \\ []) do
    {:ok, source} =
      GeoData.upsert_source(%{
        short_name: "GRUEN_BERLIN",
        name: "Grün Berlin",
        url: "#{@base_url}/presse/pressemitteilungen",
        copyright: "Grün Berlin GmbH",
        color: "#7FC241",
        background_color: "#5EA61F"
      })

    skip =
      if Keyword.get(opts, :skip_imported, true), do: imported_urls(source), else: MapSet.new()

    result =
      http_connection
      |> fetch_entries(Keyword.get(opts, :pages, @pages), skip)
      |> Enum.map(fn entry ->
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
          []
        )
      end)

    {:ok, result}
  rescue
    error ->
      Bugsnag.report(error)
      {:error, error}
  end

  @doc """
  Fetches the press releases of the first `pages` list pages including the text
  of every article. Releases whose url is in `skip` are left out.
  """
  def fetch_entries(http_connection, pages \\ @pages, skip \\ MapSet.new()) do
    http_connection
    |> list_entries(@list_url, pages, [])
    |> Enum.reject(&MapSet.member?(skip, &1.url))
    |> Enum.map(&add_article(&1, http_connection))
  end

  # Releases that are stored with their text. Ones whose article could not be
  # fetched are imported again, their text is only the title and the project.
  defp imported_urls(source) do
    from(item in NewsItem,
      where: item.source_id == ^source.id,
      where: fragment("length(?) >= ?", item.full_text, @short_text),
      select: item.external_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp list_entries(_http_connection, nil, _pages, entries), do: entries
  defp list_entries(_http_connection, _url, 0, entries), do: entries

  defp list_entries(http_connection, url, pages, entries) do
    case fetch_document(http_connection, url) do
      nil ->
        entries

      document ->
        list_entries(
          http_connection,
          next_page_url(document),
          pages - 1,
          entries ++ parse_list(document)
        )
    end
  end

  defp next_page_url(document) do
    case Floki.attribute(document, ".paginator .nextPage", "data-href") do
      [path | _] -> absolute_url(HtmlEntities.decode(path))
      [] -> nil
    end
  end

  @doc """
  The releases of one list page. Entries that are listed with a link to another
  website are kept with that link.
  """
  def parse_list(document) do
    document
    |> Floki.find(".module--news-grid a.item")
    |> Enum.map(fn item ->
      %{
        title: item |> Floki.attribute("title") |> List.first() |> to_string() |> clean(),
        url: item |> Floki.attribute("href") |> List.first() |> absolute_url(),
        projects: item |> Floki.find(".item__meta__item--type") |> Enum.map(&text([&1])),
        published_at: item |> text_of(".item__meta__item--date") |> parse_date()
      }
    end)
    |> Enum.filter(&entry?/1)
    |> Enum.uniq_by(& &1.url)
  end

  defp entry?(entry) do
    entry.title != "" && entry.published_at && is_binary(entry.url) &&
      String.starts_with?(entry.url, "http") &&
      not Enum.any?(entry.projects, &(&1 in @skipped_projects))
  end

  defp add_article(entry, http_connection) do
    {content, text} = fetch_article(entry, http_connection)

    # the projects are analyzed as well, they name the park or square the
    # release is about ("Tempelhofer Feld", "Mauerpark")
    full_text =
      [entry.title, Enum.join(entry.projects, "\n"), content, text]
      |> Enum.reject(&(&1 in ["", nil]))
      |> Enum.join("\n")

    entry
    |> Map.put(:content, content)
    |> Map.put(:full_text, full_text)
  end

  # A single broken article page must not break the whole import, the title and
  # the project are still analyzed
  defp fetch_article(entry, http_connection) do
    http_connection
    |> fetch_document(entry.url)
    |> article()
  rescue
    error ->
      Logger.warning("Could not fetch press release #{entry.url}: #{Exception.message(error)}")
      {nil, ""}
  end

  @doc """
  The teaser and the text of an article page. A release that redirects to the
  website of its project has no article here, only its title and its project
  are analyzed then.
  """
  def article(nil), do: {nil, ""}

  def article(document) do
    case Floki.find(document, ".module--single--news") do
      [] -> {nil, ""}
      news -> {teaser(news), news |> Floki.find(".module--text .inner") |> text()}
    end
  end

  # The teaser block of the page, or the bullet points and the first paragraph
  defp teaser(news) do
    case Floki.find(news, ".module--teaser .inner") do
      [] -> news |> body_blocks() |> first_paragraphs()
      blocks -> blocks |> text() |> presence()
    end
  end

  defp body_blocks(news) do
    news
    |> Floki.find(".module--text")
    |> Enum.reject(&(&1 |> Floki.attribute("class") |> to_string() =~ "module--teaser"))
    |> Floki.find(".inner")
  end

  # The bullet points before the first paragraph and that paragraph, in the
  # style of the teasers of the other press releases ("* one  * two   text")
  defp first_paragraphs(blocks) do
    blocks
    |> Enum.flat_map(&(Floki.children(&1) || []))
    |> Enum.reduce_while([], fn node, texts ->
      case {node, text([node])} do
        {{"p", _, _}, ""} ->
          {:cont, texts}

        {{"p", _, _}, paragraph} ->
          {:halt, texts ++ [paragraph]}

        {{"ul", _, _}, _} ->
          {:cont, texts ++ Enum.map(Floki.find(node, "li"), &"* #{text([&1])}")}

        _ ->
          {:cont, texts}
      end
    end)
    |> Enum.join("  ")
    |> presence()
  end

  defp text_of(document, selector) do
    document |> Floki.find(selector) |> text()
  end

  defp text(nodes) do
    nodes
    |> Floki.text(sep: " ")
    |> HtmlEntities.decode()
    |> clean()
  end

  defp clean(text) do
    text
    |> String.replace("\u00a0", " ")
    |> String.replace(~r/[^\S\n]*\n[^\S\n]*/u, "\n")
    |> String.replace(~r/[^\S\n]+/u, " ")
    |> String.trim()
  end

  defp presence(""), do: nil
  defp presence(text), do: text

  # "Donnerstag, 3. September 2026", "3. September 2026"
  defp parse_date(text) do
    with [_, day, month, year] <-
           Regex.run(~r/(\d{1,2})\.\s*(#{GermanMonths.pattern()})\s+(\d{4})/u, text),
         month = GermanMonths.number(month),
         {:ok, date} <- Date.new(String.to_integer(year), month, String.to_integer(day)) do
      date
      |> DateTime.new!(~T[00:00:00], "Europe/Berlin")
      |> DateTime.shift_zone!("Etc/UTC")
    else
      _ -> nil
    end
  end

  defp absolute_url(url) do
    case url do
      "http" <> _ -> url
      "/" <> _ -> @base_url <> url
      other -> other
    end
  end

  defp fetch_document(http_connection, url) do
    response = http_connection.get!(url, @headers, timeout: 60_000, recv_timeout: 60_000)

    if response.status_code != 200 do
      Logger.warning("Grün Berlin returned #{response.status_code} for #{url}")
      nil
    else
      # keep line breaks between the blocks, otherwise their words are glued together
      {:ok, document} =
        response.body
        |> String.replace(~r{</(p|li|h\d|div|td|tr)>|<br\s*/?>}i, "\\0\n")
        |> Floki.parse_document()

      document
    end
  end
end
