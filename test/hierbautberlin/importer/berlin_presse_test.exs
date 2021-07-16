defmodule Hierbautberlin.Importer.BerlinPresseTest do
  use Hierbautberlin.DataCase

  alias Hierbautberlin.Importer.BerlinPresse

  defmodule ImportMock do
    def get!(
          "https://www.berlin.de/presse/pressemitteilungen/index/feed?institutions%5B%5D=Presse-+und+Informationsamt+des+Landes+Berlin&institutions%5B%5D=Senatskanzlei+-+Wissenschaft+und+Forschung&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Bildung%2C+Jugend+und+Familie&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Finanzen&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Gesundheit%2C+Pflege+und+Gleichstellung&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Inneres+und+Sport&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Integration%2C+Arbeit+und+Soziales&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Justiz%2C+Verbraucherschutz+und+Antidiskriminierung&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Kultur+und+Europa&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Stadtentwicklung+und+Wohnen&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Umwelt%2C+Verkehr+und+Klimaschutz&institutions%5B%5D=Senatsverwaltung+f%C3%BCr+Wirtschaft%2C+Energie+und+Betriebe&institutions%5B%5D=Bezirksamt+Charlottenburg-Wilmersdorf&institutions%5B%5D=Bezirksamt+Friedrichshain-Kreuzberg&institutions%5B%5D=Bezirksamt+Lichtenberg&institutions%5B%5D=Bezirksamt+Marzahn-Hellersdorf&institutions%5B%5D=Bezirksamt+Mitte&institutions%5B%5D=Bezirksamt+Neuk%C3%B6lln&institutions%5B%5D=Bezirksamt+Pankow&institutions%5B%5D=Bezirksamt+Reinickendorf&institutions%5B%5D=Bezirksamt+Spandau&institutions%5B%5D=Bezirksamt+Steglitz-Zehlendorf&institutions%5B%5D=Bezirksamt+Tempelhof-Sch%C3%B6neberg&institutions%5B%5D=Bezirksamt+Treptow-K%C3%B6penick",
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
                 {13.3799820166143, 52.5189643842998}
               ],
               properties: %{},
               srid: 4326
             }

      # Try to import again
      {:ok, result} = BerlinPresse.import(ImportMock)

      assert length(result) == 2
    end
  end
end
