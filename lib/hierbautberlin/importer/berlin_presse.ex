defmodule Hierbautberlin.Importer.BerlinPresse do
  require Logger

  alias Hierbautberlin.GeoData
  alias Hierbautberlin.Services.Berlin

  @feed_url "https://www.berlin.de/presse/pressemitteilungen/index/feed?institutions%5B%5D=Presse-+und+Informationsamt+des+Landes+Berlin&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Arbeit%2C+Soziales%2C+Gleichstellung%2C+Integration%2C+Vielfalt+und+Antidiskriminierung&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Bildung%2C+Jugend+und+Familie&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Finanzen&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Inneres+und+Sport&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Justiz+und+Verbraucherschutz&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Kultur+und+Gesellschaftlichen+Zusammenhalt&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Mobilit%C3%A4t%2C+Verkehr%2C+Klimaschutz+und+Umwelt&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Stadtentwicklung%2C+Bauen+und+Wohnen&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Wirtschaft%2C+Energie+und+Betriebe&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Wissenschaft%2C+Gesundheit+und+Pflege&institutions%5B%5D=Landesdenkmalamt&institutions%5B%5D=Bezirksamt+Charlottenburg-Wilmersdorf&institutions%5B%5D=Bezirksamt+Friedrichshain-Kreuzberg&institutions%5B%5D=Bezirksamt+Lichtenberg&institutions%5B%5D=Bezirksamt+Marzahn-Hellersdorf&institutions%5B%5D=Bezirksamt+Mitte&institutions%5B%5D=Bezirksamt+Neuk%C3%B6lln&institutions%5B%5D=Bezirksamt+Pankow&institutions%5B%5D=Bezirksamt+Reinickendorf&institutions%5B%5D=Bezirksamt+Spandau&institutions%5B%5D=Bezirksamt+Steglitz-Zehlendorf&institutions%5B%5D=Bezirksamt+Tempelhof-Sch%C3%B6neberg&institutions%5B%5D=Bezirksamt+Treptow-K%C3%B6penick"

  def import(http_connection \\ Hierbautberlin.HTTPClient) do
    {:ok, source} =
      GeoData.upsert_source(%{
        short_name: "BERLIN_PRESSE",
        name: "Presseportal des Landes Berlin",
        url: "https://www.berlin.de/presse/",
        copyright: "Stadt Berlin"
      })

    result =
      http_connection
      |> fetch_entries()
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
          entry.districts
        )
      end)

    {:ok, result}
  rescue
    error ->
      Bugsnag.report(error)
      {:error, error}
  end

  @doc """
  Fetches the press releases of the given feed page (newest first) including the
  full text of each release.
  """
  def fetch_entries(http_connection, page \\ 1) do
    url = if page == 1, do: @feed_url, else: "#{@feed_url}&page=#{page}"

    http_connection
    |> fetch_rss(url)
    |> Map.get("items", [])
    |> Enum.map(&parse_entry(&1, http_connection))
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
      full_text: title <> "\n" <> content <> "\n" <> text
    }
  end

  # A single broken article page must not break the whole import, the title and
  # the teaser are still analyzed
  def fetch_text_from_html(url, http_connection) do
    response =
      http_connection.get!(
        url,
        ["User-Agent": "hierbautberlin.de"],
        timeout: 60_000,
        recv_timeout: 60_000
      )

    if response.status_code != 200 do
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
      %{}
    else
      {:ok, rss} = FastRSS.parse(response.body)
      rss
    end
  end
end
