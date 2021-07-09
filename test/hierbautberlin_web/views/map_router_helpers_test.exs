defmodule HierbautberlinWeb.MapRouteHelpersTest do
  use HierbautberlinWeb.ConnCase, async: true

  alias HierbautberlinWeb.MapRouteHelpers

  describe "route_to_map/4" do
    test "it returns a path with lat, lng, zoom and detail item", %{conn: conn} do
      assert MapRouteHelpers.route_to_map(
               conn,
               %{lat: 12.12, lng: 12.12},
               10,
               %{id: 1},
               "geo_item"
             ) ==
               "/map?lat=12.12&lng=12.12&zoom=10&details=1&detailsType=geo_item"
    end

    test "it returns a path with lat, lng, zoom and without detail item", %{conn: conn} do
      assert MapRouteHelpers.route_to_map(conn, %{lat: 12.12, lng: 12.12}, 10) ==
               "/map?lat=12.12&lng=12.12&zoom=10"
    end
  end

  describe "link_to_details/2" do
    test "it returns a link with a geo point" do
      item =
        insert(:geo_item,
          geo_point: %Geo.Point{
            coordinates: {13.2677, 52.49},
            properties: %{},
            srid: 4326
          }
        )

      assert MapRouteHelpers.link_to_details(HierbautberlinWeb.Endpoint, item) ==
               "http://localhost:4002/map?lat=52.49&lng=13.2677&details=#{item.id}&detailsType=geo_item"
    end

    test "it returns a link with a geo polygon" do
      item =
        insert(:geo_item,
          geometry: %Geo.MultiPolygon{
            coordinates: [
              [
                [
                  {13.4343272619011, 52.5405861405958},
                  {13.4371221660038, 52.5396388337848},
                  {13.4376794632698, 52.5401260460066},
                  {13.4392118915391, 52.5394073982677},
                  {13.4392324135568, 52.5395221795781},
                  {13.4343272619011, 52.5405861405958}
                ]
              ]
            ],
            properties: %{},
            srid: 4326
          }
        )

      assert MapRouteHelpers.link_to_details(HierbautberlinWeb.Endpoint, item) ==
               "http://localhost:4002/map?lat=52.53999676943175&lng=13.436779837728949&details=#{item.id}&detailsType=geo_item"
    end

    test "it returns a link to a news item with geo points" do
      item = insert(:news_item)

      assert MapRouteHelpers.link_to_details(HierbautberlinWeb.Endpoint, item) ==
               "http://localhost:4002/map?lat=52.0&lng=13.0&details=#{item.id}&detailsType=news_item"
    end

    test "it returns a link to a news item with geometries" do
      item = Map.merge(insert(:news_item), %{geo_points: nil})

      assert MapRouteHelpers.link_to_details(HierbautberlinWeb.Endpoint, item) ==
               "http://localhost:4002/map?lat=52.05&lng=13.05&details=#{item.id}&detailsType=news_item"
    end

    test "it returns a link without any geo information" do
      item = insert(:geo_item)

      assert MapRouteHelpers.link_to_details(HierbautberlinWeb.Endpoint, item) ==
               "http://localhost:4002/map?details=#{item.id}&detailsType=geo_item"
    end
  end
end
