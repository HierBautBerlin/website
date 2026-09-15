defmodule Hierbautberlin.Importer.InfraveloTest do
  use Hierbautberlin.DataCase

  alias Hierbautberlin.Importer.Infravelo
  alias Hierbautberlin.GeoData
  alias Hierbautberlin.Repo

  defmodule ImportMock do
    def get!(
          "https://www.infravelo.de/api/v1/projects/",
          ["User-Agent": "hierbautberlin.de"],
          timeout: 60_000,
          recv_timeout: 60_000
        ) do
      {:ok, html} = File.read("./test/support/data/infravelo/first.json")
      %{body: html, headers: [], status_code: 200}
    end

    def get!(
          "https://www.infravelo.de/api/v1/projects/50/50/",
          ["User-Agent": "hierbautberlin.de"],
          timeout: 60_000,
          recv_timeout: 60_000
        ) do
      {:ok, html} = File.read("./test/support/data/infravelo/second.json")
      %{body: html, headers: [], status_code: 200}
    end
  end

  defmodule ImportUpdateMock do
    def get!(
          "https://www.infravelo.de/api/v1/projects/",
          ["User-Agent": "hierbautberlin.de"],
          timeout: 60_000,
          recv_timeout: 60_000
        ) do
      {:ok, html} = File.read("./test/support/data/infravelo/update.json")
      %{body: html, headers: [], status_code: 200}
    end
  end

  defmodule DatesMock do
    def get!("https://www.infravelo.de/api/v1/projects/", _headers, _opts) do
      %{
        body: File.read!("./test/support/data/infravelo/dates.json"),
        headers: [],
        status_code: 200
      }
    end
  end

  describe "import/1" do
    test "uses the year of implementation or the milestones as dates" do
      {:ok, [year_only, milestones_only, nothing]} = Infravelo.import(DatesMock)

      # 2025 in Europe/Berlin
      assert year_only.date_start == ~U[2024-12-31 23:00:00Z]
      assert year_only.date_end == ~U[2025-12-30 23:00:00Z]
      assert year_only.title == "Rüdiger- Ecke Dietlindestr"

      assert year_only.description ==
               "Projekttyp: Anlehnbügel (Anzahl Stellplätze: 4, Anzahl Bügel: 2)\n" <>
                 "Bezirk: Lichtenberg\n" <>
                 "Vorhabenträger: Bezirksamt Lichtenberg finanziert durch Landesmitteln - Sondervermögen Infrastruktur der Wachsenden Stadt und Nachhaltigkeitsfonds\n" <>
                 "Bauherr: Bezirksamt Lichtenberg\n" <>
                 "Jahr der Umsetzung: 2025"

      # 1. Quartal 2020 to 4. Quartal 2021
      assert milestones_only.title == "Mitte – Tegel – Spandau"
      assert milestones_only.date_start == ~U[2019-12-31 23:00:00Z]
      assert milestones_only.date_end == ~U[2021-12-30 23:00:00Z]

      assert nothing.date_start == nil
      assert nothing.date_end == nil
      assert nothing.description == "Vorhabenträger: Berlin"
    end

    test "basic import of infravelo data" do
      {:ok, result} = Infravelo.import(ImportMock)
      assert length(result) == 100

      first = List.first(result) |> Repo.preload(:source)

      assert first.date_end == ~U[2022-12-30 23:00:00Z]
      assert first.date_start == ~U[2022-03-31 22:00:00Z]

      assert first.description ==
               "Die Braunschweiger Straße ist eine Nebenstraße im Neuköllner Richardkiez. Auf dem Abschnitt zwischen Sonnenallee und Niemetzstraße wird das Kopfsteinpflaster durch Asphalt ersetzt, um die Strecke für Radfahrende attraktiver zu machen. Außerdem wird der Kfz-Durchgangsverkehr reduziert, indem die Einfahrt für Kfz von der Sonnenallee verboten wird. Dadurch wird die Sicherheit und Aufenthaltsqualität für alle Verkehrsteilnehmer*innen erhöht.\n\n" <>
                 "Projekttyp: Mischverkehr, Nebenroute (Länge: 150 m)\n" <>
                 "Bezirk: Neukölln\n" <>
                 "Vorhabenträger: Senatsverwaltung für Umwelt, Verkehr und Klimaschutz\n" <>
                 "Bauherr: Bezirksamt Neukölln"

      assert first.external_id == "9080026"

      assert first.geometry == %Geo.LineString{
               coordinates: [
                 {13.4463152997, 52.4709511995},
                 {13.4478924972, 52.4711337807}
               ],
               properties: %{},
               srid: 4326
             }

      assert first.geo_point == %Geo.Point{
               coordinates: {13.4471038968, 52.4710424927},
               properties: %{},
               srid: 4326
             }

      assert first.source.short_name == "INFRAVELO"
      assert first.state == "in_planning"
      assert first.subtitle == "Per Rad durch den Richardkiez"
      assert first.title == "Braunschweiger Straße (Bauabschnitt 3)"

      assert first.url ==
               "https://www.infravelo.de/projekt/braunschweiger-strasse-bauabschnitt-3-2/"
    end

    test "Updates an entry" do
      {:ok, result} = Infravelo.import(ImportMock)

      first = List.first(result)

      assert first.external_id == "9080026"
      assert first.title == "Braunschweiger Straße (Bauabschnitt 3)"

      {:ok, result} = Infravelo.import(ImportUpdateMock)
      second = GeoData.get_geo_item!(List.first(result).id)

      assert first.id == second.id
      assert second.external_id == "9080026"
      assert second.title == "Braunschweiger Straße (Bauabschnitt 3) - Update"
    end
  end
end
