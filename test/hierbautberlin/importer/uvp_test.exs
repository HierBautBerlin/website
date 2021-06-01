defmodule Hierbautberlin.Importer.UVPTest do
  use Hierbautberlin.DataCase

  alias Hierbautberlin.Importer.UVP
  alias Hierbautberlin.Repo
  alias Hierbautberlin.GeoData

  defmodule ImportMock do
    def get!(
          "https://www.uvp-verbund.de/portal/_ns:ZzMwX18zMXxpbWFya2VyNA__/main-maps.psml",
          ["User-Agent": "hierbautberlin.de"],
          timeout: 60_000,
          recv_timeout: 60_000
        ) do
      {:ok, html} = File.read("./test/support/data/uvp/uvp.js")
      %{body: html, headers: [], status_code: 200}
    end
  end

  defmodule ImportUpdateMock do
    def get!(
          "https://www.uvp-verbund.de/portal/_ns:ZzMwX18zMXxpbWFya2VyNA__/main-maps.psml",
          ["User-Agent": "hierbautberlin.de"],
          timeout: 60_000,
          recv_timeout: 60_000
        ) do
      {:ok, html} = File.read("./test/support/data/uvp/uvp_update.js")
      %{body: html, headers: [], status_code: 200}
    end
  end

  describe "import/1" do
    test "basic import of infravelo data" do
      result = UVP.import(ImportMock)
      assert length(result) == 3419

      first = List.first(result) |> Repo.preload(:source)

      assert first.external_id == "294BDB79-9CB1-43C0-A98D-FFBA0B1C85E0"
      assert first.geo_geometry == nil

      assert first.geo_point == %Geo.Point{
               coordinates: {13.248999999999999, 51.96115},
               properties: %{},
               srid: 4326
             }

      assert first.source.short_name == "UVP"
      assert first.title == "Beregnung in der Gemarkung Schlenzer"

      assert first.url ==
               "https://www.uvp-verbund.de/trefferanzeige?docuuid=294BDB79-9CB1-43C0-A98D-FFBA0B1C85E0"
    end

    test "Updates an entry" do
      first = ImportMock |> UVP.import() |> List.first()

      assert first.external_id == "294BDB79-9CB1-43C0-A98D-FFBA0B1C85E0"
      assert first.title == "Beregnung in der Gemarkung Schlenzer"

      second = ImportUpdateMock |> UVP.import() |> List.first()
      second = GeoData.get_geo_item!(second.id)

      assert first.id == second.id

      assert second.external_id == "294BDB79-9CB1-43C0-A98D-FFBA0B1C85E0"
      assert second.title == "Beregnung in der Gemarkung Schlenzer - Update"
    end
  end
end
