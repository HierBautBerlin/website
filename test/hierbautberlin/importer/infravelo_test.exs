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

  describe "import/1" do
    test "basic import of infravelo data" do
      result = Infravelo.import(ImportMock)
      assert length(result) == 100

      first = List.first(result) |> Repo.preload(:source)

      assert first.date_end == ~U[2022-12-30 23:00:00Z]
      assert first.date_start == ~U[2022-03-31 22:00:00Z]

      assert first.description ==
               "Die Braunschweiger Straße ist eine Nebenstraße im Neuköllner Richardkiez. Auf dem Abschnitt zwischen Sonnenallee und Niemetzstraße wird das Kopfsteinpflaster durch Asphalt ersetzt, um die Strecke für Radfahrende attraktiver zu machen. Außerdem wird der Kfz-Durchgangsverkehr reduziert, indem die Einfahrt für Kfz von der Sonnenallee verboten wird. Dadurch wird die Sicherheit und Aufenthaltsqualität für alle Verkehrsteilnehmer*innen erhöht."

      assert first.external_id == "9080026"

      assert first.geo_geometry == %Geo.LineString{
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
      first = ImportMock |> Infravelo.import() |> List.first()

      assert first.external_id == "9080026"
      assert first.title == "Braunschweiger Straße (Bauabschnitt 3)"

      second = ImportUpdateMock |> Infravelo.import() |> List.first()
      second = GeoData.get_geo_item!(second.id)

      assert first.id == second.id
      assert second.external_id == "9080026"
      assert second.title == "Braunschweiger Straße (Bauabschnitt 3) - Update"
    end
  end
end
