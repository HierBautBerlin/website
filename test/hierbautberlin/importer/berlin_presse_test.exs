defmodule Hierbautberlin.Importer.BerlinPresseTest do
  use Hierbautberlin.DataCase

  alias Hierbautberlin.Importer.BerlinPresse

  defmodule ImportMock do
    def get!(
          "https://www.berlin.de/presse/pressemitteilungen/index/feed?institutions%5B%5D=Presse-+und+Informationsamt+des+Landes+Berlin&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Arbeit%2C+Soziales%2C+Gleichstellung%2C+Integration%2C+Vielfalt+und+Antidiskriminierung&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Bildung%2C+Jugend+und+Familie&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Finanzen&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Inneres+und+Sport&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Justiz+und+Verbraucherschutz&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Kultur+und+Gesellschaftlichen+Zusammenhalt&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Mobilit%C3%A4t%2C+Verkehr%2C+Klimaschutz+und+Umwelt&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Stadtentwicklung%2C+Bauen+und+Wohnen&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Wirtschaft%2C+Energie+und+Betriebe&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Wissenschaft%2C+Gesundheit+und+Pflege&institutions%5B%5D=Landesdenkmalamt&institutions%5B%5D=Bezirksamt+Charlottenburg-Wilmersdorf&institutions%5B%5D=Bezirksamt+Friedrichshain-Kreuzberg&institutions%5B%5D=Bezirksamt+Lichtenberg&institutions%5B%5D=Bezirksamt+Marzahn-Hellersdorf&institutions%5B%5D=Bezirksamt+Mitte&institutions%5B%5D=Bezirksamt+Neuk%C3%B6lln&institutions%5B%5D=Bezirksamt+Pankow&institutions%5B%5D=Bezirksamt+Reinickendorf&institutions%5B%5D=Bezirksamt+Spandau&institutions%5B%5D=Bezirksamt+Steglitz-Zehlendorf&institutions%5B%5D=Bezirksamt+Tempelhof-Sch%C3%B6neberg&institutions%5B%5D=Bezirksamt+Treptow-K%C3%B6penick",
          ["User-Agent": "hierbautberlin.de"],
          timeout: 60_000,
          recv_timeout: 60_000
        ) do
      {:ok, html} = File.read("./test/support/data/berlin_presse/feed.xml")
      %{body: html, headers: [], status_code: 200}
    end

    def get!(
          "https://www.berlin.de/sen/finanzen/presse/pressemitteilungen/pressemitteilung.1102315.php",
          ["User-Agent": "hierbautberlin.de"],
          timeout: 60_000,
          recv_timeout: 60_000
        ) do
      {:ok, html} = File.read("./test/support/data/berlin_presse/pressemitteilung.1102315.html")
      %{body: html, headers: [], status_code: 200}
    end

    def get!(
          "https://www.berlin.de/ba-charlottenburg-wilmersdorf/aktuelles/pressemitteilungen/2021/pressemitteilung.1102306.php",
          ["User-Agent": "hierbautberlin.de"],
          timeout: 60_000,
          recv_timeout: 60_000
        ) do
      {:ok, html} = File.read("./test/support/data/berlin_presse/pressemitteilung.1102306.html")
      %{body: html, headers: [], status_code: 200}
    end
  end

  defmodule ArchiveMock do
    # every page returns the same feed, like the pages after the last one do
    def get!("https://www.berlin.de/presse/pressemitteilungen/index/feed?" <> _ = url, _, _) do
      send(self(), {:get, url})
      {:ok, html} = File.read("./test/support/data/berlin_presse/feed.xml")
      %{body: html, headers: [], status_code: 200}
    end

    def get!(url, headers, opts) do
      send(self(), {:get, url})
      ImportMock.get!(url, headers, opts)
    end
  end

  describe "import/1" do
    test "basic import of berlin presse data" do
      street_one = insert(:street, name: "Suarezstraße")
      street_two = insert(:street, name: "Pestalozzistraße")
      street_three = insert(:street, name: "Kantstraße")

      street_four = insert(:street, name: "Weidenstraße")
      street_number = insert(:street_number, number: "22", geo_street_id: street_four.id)

      Hierbautberlin.GeoData.AnalyzeText.add_streets([
        street_one,
        street_two,
        street_three,
        street_four
      ])

      park = insert(:place, name: "Testpark")
      Hierbautberlin.GeoData.AnalyzeText.add_places([park])

      {:ok, result} = BerlinPresse.import(ImportMock)

      assert length(result) == 2
      [first, second] = result

      first = Repo.preload(first, :source)

      assert first.title == "Stromnetz Berlin ist wieder im Eigentum des Landes Berlin"

      assert first.external_id ==
               "https://www.berlin.de/sen/finanzen/presse/pressemitteilungen/pressemitteilung.1102315.php"

      assert first.content ==
               "* Transaktion ist jetzt formal abgeschlossen  * Gemeinsames Hissen der Berlin-Flagge symbolisiert Rückkehr zum Land Berlin   Die Stromnetz Berlin GmbH ist heute offiziell wieder in das Eigentum des Landes Berlin übergegangen. Mit einem gemeinsamen Hissen der Berlin-Flagge haben Vertreterinnen und Vertreter des Landes sowie der Vattenfall GmbH und der Stromnetz GmbH den Übergang symbolisch vollzogen."

      assert first.url ==
               "https://www.berlin.de/sen/finanzen/presse/pressemitteilungen/pressemitteilung.1102315.php"

      assert first.published_at == ~U[2021-07-01 14:50:00Z]
      assert first.source.name == "Presseportal des Landes Berlin"

      assert Enum.empty?(first.geo_streets)
      assert Enum.empty?(first.geo_street_numbers)
      assert Enum.empty?(first.geo_places)

      second = Repo.preload(second, :source)

      assert second.title == "Gehweg- und Fahrbahnsanierungen an der Suarezstraße"

      assert second.external_id ==
               "https://www.berlin.de/ba-charlottenburg-wilmersdorf/aktuelles/pressemitteilungen/2021/pressemitteilung.1102306.php"

      assert second.content ==
               "Der Gehweg an der Ostseite der Suarezstraße zwischen Kant- und Pestalozzistraße wird ab Montag, 5. Juni 2021, grundhaft erneuert. Der Gehweg wird neben dem 6,5 Meter breiten Plattenbelag künftig einen schmalen Begleitstreifen aus Mosaikpflaster aufweisen und mit Abstelleinrichtungen für Fahrräder ausgestattet werden. Zeitgleich wird die Bushaltestelle der Linie 209 an der Suarezstraße ausgebaut, so dass diese barrierefrei für Gelenkbusse wird."

      assert second.url ==
               "https://www.berlin.de/ba-charlottenburg-wilmersdorf/aktuelles/pressemitteilungen/2021/pressemitteilung.1102306.php"

      assert second.published_at == ~U[2021-07-01 14:05:00Z]
      assert second.source.name == "Presseportal des Landes Berlin"

      assert second.geo_streets |> Enum.map(& &1.id) |> Enum.sort() == [
               street_one.id,
               street_two.id,
               street_three.id
             ]

      assert second.geo_street_numbers |> Enum.map(& &1.id) == [street_number.id]
      assert second.geo_places |> Enum.map(& &1.id) == [park.id]

      assert second.geo_points == %Geo.MultiPoint{
               coordinates: [
                 {13, 52},
                 {13, 52},
                 {13, 52},
                 {13.0, 52.0},
                 {13.2679, 52.51}
               ],
               properties: %{},
               srid: 4326
             }

      # Try to import again
      {:ok, result} = BerlinPresse.import(ImportMock)

      assert length(result) == 2
    end
  end

  describe "import_archive/2" do
    test "reads the pages until one repeats and skips stored releases" do
      {:ok, result} = BerlinPresse.import_archive(ArchiveMock, 10)

      assert result |> Enum.map(& &1.title) |> Enum.sort() == [
               "Gehweg- und Fahrbahnsanierungen an der Suarezstraße",
               "Stromnetz Berlin ist wieder im Eigentum des Landes Berlin"
             ]

      assert_received {:get, "https://www.berlin.de/presse/pressemitteilungen/index/feed?" <> _}

      assert_received {:get,
                       "https://www.berlin.de/presse/pressemitteilungen/index/feed?" <> page_two}

      assert page_two =~ "&page=2"
      refute page_two =~ "Bezirksamt"

      flush_requests()
      {:ok, result} = BerlinPresse.import_archive(ArchiveMock, 10)
      assert result == []
      refute_received {:get, "https://www.berlin.de/sen/" <> _}
    end
  end

  defp flush_requests do
    receive do
      {:get, _} -> flush_requests()
    after
      0 -> :ok
    end
  end

  describe "strip_html/1" do
    test "extracts the text of the current page layout" do
      text =
        "test/support/data/berlin_presse/pressemitteilung_2026.html"
        |> File.read!()
        |> BerlinPresse.strip_html()

      assert text =~ "Rund um den World Cleanup Day am 20. September"
      refute text =~ "Direkt zur Kontaktinformation"
    end
  end
end
