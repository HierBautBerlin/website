defmodule Hierbautberlin.Importer.BerlinPresse do
  alias Hierbautberlin.GeoData
  alias Hierbautberlin.Services.Berlin

  def import(http_connection \\ HTTPoison) do
    {:ok, source} =
      GeoData.upsert_source(%{
        short_name: "BERLIN_PRESSE",
        name: "Presseportal des Landes Berlin",
        url: "https://www.berlin.de/presse/",
        copyright: "Stadt Berlin"
      })

    feed =
      fetch_rss(
        http_connection,
        "https://www.berlin.de/presse/pressemitteilungen/index/feed?institutions%5B%5D=Presse-+und+Informationsamt+des+Landes+Berlin&institutions%5B%5D=Senatskanzlei+-+Wissenschaft+und+Forschung&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Bildung%2C+Jugend+und+Familie&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Finanzen&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Gesundheit%2C+Pflege+und+Gleichstellung&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Inneres+und+Sport&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Integration%2C+Arbeit+und+Soziales&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Justiz%2C+Verbraucherschutz+und+Antidiskriminierung&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Kultur+und+Europa&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Stadtentwicklung+und+Wohnen&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Umwelt%2C+Verkehr+und+Klimaschutz&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Wirtschaft%2C+Energie+und+Betriebe&institutions%5B%5D=Bezirksamt+Charlottenburg-Wilmersdorf&institutions%5B%5D=Bezirksamt+Friedrichshain-Kreuzberg&institutions%5B%5D=Bezirksamt+Lichtenberg&institutions%5B%5D=Bezirksamt+Marzahn-Hellersdorf&institutions%5B%5D=Bezirksamt+Mitte&institutions%5B%5D=Bezirksamt+Neuk%C3%B6lln&institutions%5B%5D=Bezirksamt+Pankow&institutions%5B%5D=Bezirksamt+Reinickendorf&institutions%5B%5D=Bezirksamt+Spandau&institutions%5B%5D=Bezirksamt+Steglitz-Zehlendorf&institutions%5B%5D=Bezirksamt+Tempelhof-Sch%C3%B6neberg&institutions%5B%5D=Bezirksamt+Treptow-K%C3%B6penick"
      )

    result =
      Enum.map(feed["items"], fn entry ->
        parse_entry(entry, http_connection, source)
      end)

    {:ok, result}
  rescue
    error ->
      Bugsnag.report(error)
      {:error, error}
  end

  defp parse_entry(entry, http_connection, source) do
    title = HtmlEntities.decode(entry["title"])
    content = HtmlEntities.decode(entry["description"])
    url = entry["link"]

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
    full_text = title <> "\n" <> content <> "\n" <> text

    GeoData.create_news_item!(
      %{
        external_id: url,
        title: title,
        url: url,
        content: content,
        published_at: published,
        source_id: source.id
      },
      full_text,
      districts
    )
  end

  defp fetch_text_from_html(url, http_connection) do
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
  end

  defp strip_html(text) do
    {:ok, document} = Floki.parse_document(text)

    document
    |> Floki.find(".article[role='main']")
    |> Floki.raw_html()
    |> Floki.text()
    |> String.replace(~r/^\s*(Kontakt(e)?|Pressekontakt(e)?):.*\z/sm, "")
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
