defmodule Hierbautberlin.Importer.UVPTest do
  use Hierbautberlin.DataCase

  alias Hierbautberlin.GeoData
  alias Hierbautberlin.Importer.UVP
  alias Hierbautberlin.Repo

  defmodule ImportMock do
    def get!(url, ["User-Agent": "hierbautberlin.de"], timeout: 60_000, recv_timeout: 60_000) do
      body =
        case url do
          "https://www.uvp-verbund.de/rest/getMapMarkers?legend=obj_class_zv&page=1" ->
            File.read!(
              "./test/support/data/uvp/#{Process.get(:uvp_fixture, "markers_page_1")}.json"
            )

          _other ->
            "[]"
        end

      %{body: body, headers: [], status_code: 200}
    end
  end

  describe "import/1" do
    test "imports the procedures in the Berlin area" do
      {:ok, result} = UVP.import(ImportMock, delay: 0)
      assert length(result) == 2

      first = List.first(result) |> Repo.preload(:source)

      assert first.external_id == "0F8A6A66-A2F9-40EE-A426-AD2C013622DB"
      assert first.geometry == nil
      assert first.geo_point == %Geo.Point{coordinates: {13.61585, 52.3477}, srid: 4326}
      assert first.source.short_name == "UVP"
      assert first.title == "Ausbau de L 401 in der Ortsdurchfahrt Zeuthen"
      assert first.subtitle == "Zulassungsverfahren"

      assert first.url ==
               "https://www.uvp-verbund.de/trefferanzeige?docuuid=0F8A6A66-A2F9-40EE-A426-AD2C013622DB"
    end

    test "updates an entry" do
      {:ok, [first | _]} = UVP.import(ImportMock, delay: 0)

      Process.put(:uvp_fixture, "markers_update")
      {:ok, [updated]} = UVP.import(ImportMock, delay: 0)

      second = GeoData.get_geo_item!(updated.id)
      assert first.id == second.id
      assert second.title == "Ausbau de L 401 in der Ortsdurchfahrt Zeuthen - Update"
    end
  end
end
