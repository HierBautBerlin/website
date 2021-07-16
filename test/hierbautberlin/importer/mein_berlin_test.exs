defmodule Hierbautberlin.Importer.MeinBerlinTest do
  use Hierbautberlin.DataCase

  alias Hierbautberlin.Importer.MeinBerlin
  alias Hierbautberlin.Repo
  alias Hierbautberlin.GeoData

  defmodule ImportMock do
    def get!(
          "https://mein.berlin.de/api/projects/?format=json",
          ["User-Agent": "hierbautberlin.de"],
          timeout: 60_000,
          recv_timeout: 60_000
        ) do
      {:ok, html} = File.read("./test/support/data/meinberlin/projects.json")
      %{body: html, headers: [], status_code: 200}
    end

    def get!(
          "https://mein.berlin.de/api/plans/?format=json",
          ["User-Agent": "hierbautberlin.de"],
          timeout: 60_000,
          recv_timeout: 60_000
        ) do
      {:ok, html} = File.read("./test/support/data/meinberlin/plans.json")
      %{body: html, headers: [], status_code: 200}
    end
  end

  defmodule ImportUpdateMock do
    def get!(
          "https://mein.berlin.de/api/projects/?format=json",
          ["User-Agent": "hierbautberlin.de"],
          timeout: 60_000,
          recv_timeout: 60_000
        ) do
      {:ok, html} = File.read("./test/support/data/meinberlin/projects_update.json")
      %{body: html, headers: [], status_code: 200}
    end

    def get!(
          "https://mein.berlin.de/api/plans/?format=json",
          ["User-Agent": "hierbautberlin.de"],
          timeout: 60_000,
          recv_timeout: 60_000
        ) do
      %{body: "[]", headers: [], status_code: 200}
    end
  end

  describe "import/1" do
    test "basic import of infravelo data" do
      {:ok, result} = MeinBerlin.import(ImportMock)
      assert length(result) == 465

      first = List.first(result) |> Repo.preload(:source)

      assert first.description ==
               "Machen Sie Vorschläge, um Politik und Verwaltung dabei zu unterstützen, die knappen Finanzen des Bezirks bedarfsgerecht einzusetzen."

      assert first.external_id == "/projekte/burgerhaushalt-treptow-kopenick/"
      assert first.source.short_name == "MEIN_BERLIN"
      assert first.state == "finished"
      assert first.subtitle == "Bezirksamt Treptow-Köpenick"
      assert first.title == "Bürgerhaushalt Treptow-Köpenick"
      assert first.url == "https://mein.berlin.de/projekte/burgerhaushalt-treptow-kopenick/"
      assert first.geometry == nil
      assert first.geo_point == nil
      assert first.participation_open == false

      last = List.last(result) |> Repo.preload(:source)

      assert last.external_id == "/vorhaben/2019-00002/"
      assert last.geometry == nil

      assert last.geo_point == %Geo.Point{
               coordinates: {13.452748, 52.46358},
               properties: %{},
               srid: 4326
             }

      assert last.source.short_name == "MEIN_BERLIN"
      assert last.state == "active"
      assert last.subtitle == "infraVelo"
      assert last.title == "Radschnellverbindung \"Y-Trasse\""
      assert last.url == "https://mein.berlin.de/vorhaben/2019-00002/"
      assert last.participation_open == true
    end

    test "Updates an entry" do
      {:ok, result} = MeinBerlin.import(ImportMock)

      first = List.first(result)

      assert first.external_id == "/projekte/burgerhaushalt-treptow-kopenick/"
      assert first.title == "Bürgerhaushalt Treptow-Köpenick"
      assert first.date_updated == ~U[2019-02-13 14:40:17Z]

      {:ok, result} = MeinBerlin.import(ImportUpdateMock)
      second = GeoData.get_geo_item!(List.first(result).id)

      assert(first.id == second.id)
      assert second.external_id == "/projekte/burgerhaushalt-treptow-kopenick/"
      assert second.title == "Bürgerhaushalt Treptow-Köpenick Update"
    end
  end
end
