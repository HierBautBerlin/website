defmodule Hierbautberlin.Importer.BerlinBebauungsplaeneTest do
  use Hierbautberlin.DataCase

  alias Hierbautberlin.Importer.BerlinBebauungsplaene
  alias Hierbautberlin.Repo
  alias Hierbautberlin.GeoData

  defmodule ImportMock do
    def get!(
          "https://bplan-prod.liqd.net/api/bplan/multipolygons/?format=json",
          ["User-Agent": "hierbautberlin.de"],
          timeout: 60_000,
          recv_timeout: 60_000
        ) do
      {:ok, html} = File.read("./test/support/data/berlin_bebauungsplaene/polygons.json")
      %{body: html, headers: [], status_code: 200}
    end

    def get!(
          "https://bplan-prod.liqd.net/api/bplan/data/?format=json",
          ["User-Agent": "hierbautberlin.de"],
          timeout: 60_000,
          recv_timeout: 60_000
        ) do
      {:ok, html} = File.read("./test/support/data/berlin_bebauungsplaene/plans.json")
      %{body: html, headers: [], status_code: 200}
    end
  end

  defmodule ImportUpdateMock do
    def get!(
          "https://bplan-prod.liqd.net/api/bplan/multipolygons/?format=json",
          ["User-Agent": "hierbautberlin.de"],
          timeout: 60_000,
          recv_timeout: 60_000
        ) do
      {:ok, html} = File.read("./test/support/data/berlin_bebauungsplaene/polygons.json")
      %{body: html, headers: [], status_code: 200}
    end

    def get!(
          "https://bplan-prod.liqd.net/api/bplan/data/?format=json",
          ["User-Agent": "hierbautberlin.de"],
          timeout: 60_000,
          recv_timeout: 60_000
        ) do
      {:ok, html} = File.read("./test/support/data/berlin_bebauungsplaene/plans_update.json")
      %{body: html, headers: [], status_code: 200}
    end
  end

  describe "import/1" do
    test "basic import of Berliner Bebauungspläne" do
      result = BerlinBebauungsplaene.import(ImportMock)

      assert length(result) == 1

      first = List.first(result) |> Repo.preload(:source)

      assert first.external_id == "xii-181"

      assert first.geo_geometry == %Geo.MultiPolygon{
               coordinates: [
                 [
                   [
                     {13.3351788683347, 52.4183750845554},
                     {13.3351190993414, 52.4183556510473},
                     {13.3350660593876, 52.4183059223699},
                     {13.3350936352359, 52.4182678242268},
                     {13.3352320764616, 52.418315128533},
                     {13.3353269480173, 52.4182062871829},
                     {13.3350676512457, 52.4176996601486},
                     {13.3357027109838, 52.4175830601179},
                     {13.3358396852742, 52.4178530553038},
                     {13.3362872779162, 52.4179859547879},
                     {13.3360999280521, 52.4182172792362},
                     {13.3368592086943, 52.4184282038231},
                     {13.3357792779154, 52.4198783721552},
                     {13.3343298437856, 52.4194887609235},
                     {13.3351788683347, 52.4183750845554}
                   ]
                 ]
               ],
               properties: %{},
               srid: 4326
             }

      assert first.source.short_name == "BERLIN_BEBAUUNGSPLAENE"
      assert first.participation_open == false
      assert first.state == "finished"
      assert first.title == "XII - 181 - Mariannenstr., Pößneckerstr., Georgenstr."
      assert first.url == "http://fbinter.stadt-berlin.de/ScansBPlan/06_steg-zeh/xii-181.html"
      assert first.date_start == ~U[1966-11-28 00:00:00Z]
      assert first.date_end == ~U[1978-04-08 00:00:00Z]
    end

    test "Updates an entry" do
      first = ImportMock |> BerlinBebauungsplaene.import() |> List.first()

      assert first.external_id == "xii-181"
      assert first.title == "XII - 181 - Mariannenstr., Pößneckerstr., Georgenstr."

      second = ImportUpdateMock |> BerlinBebauungsplaene.import() |> List.first()
      second = GeoData.get_geo_item!(second.id)

      assert first.id == second.id

      assert second.external_id == "xii-181"
      assert second.title == "XII - 181 - Mariannenstr., Pößneckerstr., Georgenstr. - Update"
      assert second.additional_link == "http://example.com/update.html"
      assert second.additional_link_name == "Begründung"
    end
  end
end
