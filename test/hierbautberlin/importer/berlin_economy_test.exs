defmodule Hierbautberlin.Importer.BerlinEconomyTest do
  use Hierbautberlin.DataCase

  alias Hierbautberlin.Importer.BerlinEconomy
  alias Hierbautberlin.Repo
  alias Hierbautberlin.GeoData

  defmodule ImportMock do
    def get!(
          "https://www.berlin.de/wirtschaft/bauprojekte/rubric.geojson?_rnd=448764",
          ["User-Agent": "hierbautberlin.de"],
          timeout: 60_000,
          recv_timeout: 60_000
        ) do
      {:ok, html} = File.read("./test/support/data/berlin_economy/geo.json")
      %{body: html, headers: [], status_code: 200}
    end
  end

  defmodule ImportUpdateMock do
    def get!(
          "https://www.berlin.de/wirtschaft/bauprojekte/rubric.geojson?_rnd=448764",
          ["User-Agent": "hierbautberlin.de"],
          timeout: 60_000,
          recv_timeout: 60_000
        ) do
      {:ok, html} = File.read("./test/support/data/berlin_economy/geo_update.json")
      %{body: html, headers: [], status_code: 200}
    end
  end

  describe "import/1" do
    test "basic import of infravelo data" do
      {:ok, result} = BerlinEconomy.import(ImportMock)
      assert length(result) == 24

      first = List.first(result) |> Repo.preload(:source)

      assert first.description ==
               "Im Quartier Heidestraße entstehen neben dem bereits fertiggestellen QH Track drei weitere Gebäude für Wohnraum und Gewerbe. "

      assert first.external_id ==
               "https://www.berlin.de/wirtschaft/bauprojekte/6281921-4470362-mix-it-like-berlin-in-der-heidestrasse.html"

      assert first.geometry == nil

      assert first.geo_point == %Geo.Point{
               coordinates: {13.3681, 52.5295},
               properties: %{},
               srid: 4326
             }

      assert first.date_updated == ~U[2021-03-24 13:51:44Z]
      assert first.participation_open == false
      assert first.source.short_name == "BERLIN_ECONOMY"
      assert first.state == nil
      assert first.subtitle == nil
      assert first.title == "Mix it like Berlin in der Heidestraße"

      assert first.url ==
               "https://www.berlin.de/wirtschaft/bauprojekte/6281921-4470362-mix-it-like-berlin-in-der-heidestrasse.html"
    end

    test "Updates an entry" do
      {:ok, result} = BerlinEconomy.import(ImportMock)

      first = List.first(result)

      assert first.external_id ==
               "https://www.berlin.de/wirtschaft/bauprojekte/6281921-4470362-mix-it-like-berlin-in-der-heidestrasse.html"

      assert first.title == "Mix it like Berlin in der Heidestraße"
      assert first.date_updated == ~U[2021-03-24 13:51:44Z]

      {:ok, result} = BerlinEconomy.import(ImportUpdateMock)
      second = GeoData.get_geo_item!(List.first(result).id)

      assert first.id == second.id

      assert second.external_id ==
               "https://www.berlin.de/wirtschaft/bauprojekte/6281921-4470362-mix-it-like-berlin-in-der-heidestrasse.html"

      assert second.title == "Mix it like Berlin in der Heidestraße - Update"
      assert second.date_updated == ~U[2021-05-24 13:51:44Z]
    end
  end
end
