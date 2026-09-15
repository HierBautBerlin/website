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
    test "basic import of mein berlin data" do
      {:ok, result} = MeinBerlin.import(ImportMock)
      assert length(result) == 26

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

      assert last.external_id == "/vorhaben/2026-01480/"
      assert last.geometry == nil

      assert last.geo_point == %Geo.Point{
               coordinates: {13.455687, 52.45342},
               properties: %{},
               srid: 4326
             }

      assert last.source.short_name == "MEIN_BERLIN"
      assert last.state == "active"
      assert last.subtitle == "Bezirksamt Neukölln"
      assert last.title == "Innenentwicklungskonzept Haarlemer Straße"
      assert last.url == "https://mein.berlin.de/vorhaben/2026-01480/"
      assert last.date_updated == ~U[2026-09-10 19:22:09Z]
      assert last.participation_open == false

      # a running plan is no participation
      plan = Enum.find(result, &(&1.external_id == "/vorhaben/2026-01486/"))
      assert plan.participation_open == false
      assert plan.importance == 1.0

      open =
        Enum.find(result, &(&1.external_id == "/projekte/ambrosia-standorte-im-land-berlin/"))

      assert open.participation_open == true
      assert open.importance == 3.0
      assert open.relevant_until == ~U[2026-10-01 21:59:00Z]

      # participation phases over years are processes
      long =
        Enum.find(
          result,
          &(&1.external_id == "/projekte/verkehrsplanung-mobilitatspunkte-im-bezirk-charlot/")
        )

      assert long.participation_open == true
      assert long.importance == 1.5

      upcoming =
        Enum.find(
          result,
          &(&1.external_id == "/projekte/vorbereitende-untersuchungen-ehemaliger-guterbahnh/")
        )

      assert upcoming.participation_open == false
      assert upcoming.importance == 2.0
      assert upcoming.relevant_from == ~U[2026-09-21 21:59:00Z]

      old = Enum.find(result, &(&1.external_id == "/projekte/kiezkasse-planterwald-2018/"))
      assert old.participation_open == false
      assert old.relevant_until == ~U[2018-04-16 21:59:00Z]
      assert Enum.any?(result, &(&1.state == "intended"))
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
