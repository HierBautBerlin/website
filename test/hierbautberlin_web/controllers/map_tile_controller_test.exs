defmodule HierbautberlinWeb.MapTileControllerTest do
  use HierbautberlinWeb.ConnCase

  alias Hierbautberlin.GeoData.MapFeatures

  describe "GET /tiles/items/:version/:z/:x/:y" do
    test "returns a vector tile", %{conn: conn} do
      insert(:geo_item, geo_point: %Geo.Point{coordinates: {13.2679, 52.51}, srid: 4326})
      MapFeatures.refresh()

      conn = get(conn, "/tiles/items/abc/15/17591/10747.mvt")

      body = response(conn, 200)

      # the properties interactiveMap.ts filters with (MVT keys are plain strings)
      for key <- ~w(source_id outdated) do
        assert :binary.match(body, key) != :nomatch
      end

      assert response_content_type(conn, :"vnd.mapbox-vector-tile") =~
               "application/vnd.mapbox-vector-tile"

      assert get_resp_header(conn, "cache-control") == ["public, max-age=86400"]
    end

    test "returns 204 for empty tiles", %{conn: conn} do
      conn = get(conn, "/tiles/items/abc/15/0/0.mvt")
      assert response(conn, 204)
    end

    test "returns 400 for invalid coordinates", %{conn: conn} do
      assert conn |> get("/tiles/items/abc/foo/0/0.mvt") |> response(400)
      # outside of the tile grid of the zoom level
      assert conn |> get("/tiles/items/abc/14/99999/99999.mvt") |> response(400)
      assert conn |> get("/tiles/items/abc/14/-1/0.mvt") |> response(400)
    end
  end
end
