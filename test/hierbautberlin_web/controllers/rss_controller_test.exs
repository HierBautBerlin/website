defmodule HierbautberlinWeb.RSSControllerTest do
  use HierbautberlinWeb.ConnCase, async: true
  import SweetXml

  alias Ecto.Adapters.SQL

  describe "GET /rss/lat/lng" do
    setup do
      insert(:geo_item,
        title: "Distant Point Item",
        geo_point: %Geo.Point{
          coordinates: {13, 52},
          properties: %{},
          srid: 4326
        }
      )

      old_item =
        insert(:geo_item,
          title: "Old Point Item",
          geo_point: %Geo.Point{
            coordinates: {13.3789047176, 52.51650032279},
            properties: %{},
            srid: 4326
          }
        )

      SQL.query!(
        Hierbautberlin.Repo,
        "UPDATE geo_items SET inserted_at = '2010-01-01 4:30' WHERE id= $1",
        [old_item.id]
      )

      one =
        insert(:geo_item,
          title: "Point Item",
          geo_point: %Geo.Point{
            coordinates: {13.26805, 52.525},
            properties: %{},
            srid: 4326
          }
        )

      two =
        insert(:geo_item,
          title: "Polygon Item",
          geometry: %Geo.MultiPolygon{
            coordinates: [
              [
                [
                  {13.26805, 52.525},
                  {13.26805, 52.530},
                  {13.26810, 52.530},
                  {13.26805, 52.525}
                ]
              ]
            ]
          }
        )

      three = insert(:news_item)
      old_news = insert(:news_item, title: "Old News")

      SQL.query!(
        Hierbautberlin.Repo,
        "UPDATE news_items SET inserted_at = '2010-01-01 4:30' WHERE id= $1",
        [old_news.id]
      )

      {:ok, one: one, two: two, three: three}
    end

    test "returns a valid rss feed with nice items", %{
      conn: conn,
      one: one,
      two: two,
      three: three
    } do
      conn = get(conn, Routes.rss_path(conn, :show, "13.2679", "52.51"))
      doc = response(conn, 200)

      result =
        doc
        |> xpath(~x"//entry"l,
          id: ~x"./id/text()"s,
          link: ~x"./link/@href"s,
          title: ~x"./title/text()"s,
          content: ~x"./content/text()"s
        )

      assert result == [
               %{
                 content: "\n      <p>This is a description</p>\n\n      ",
                 id:
                   "http://localhost:4002/map?lat=52.525&lng=13.26805&details=#{one.id}&detailsType=geo_item",
                 link:
                   "http://localhost:4002/map?lat=52.525&lng=13.26805&details=#{one.id}&detailsType=geo_item",
                 title: "Point Item"
               },
               %{
                 content: "\n      <p>This is a description</p>\n\n      ",
                 id:
                   "http://localhost:4002/map?lat=52.5275&lng=13.268075&details=#{two.id}&detailsType=geo_item",
                 link:
                   "http://localhost:4002/map?lat=52.5275&lng=13.268075&details=#{two.id}&detailsType=geo_item",
                 title: "Polygon Item"
               },
               %{
                 content: "\n      <p>This is a nice content</p>\n\n      ",
                 id:
                   "http://localhost:4002/map?lat=52.0&lng=13.0&details=#{three.id}&detailsType=news_item",
                 link:
                   "http://localhost:4002/map?lat=52.0&lng=13.0&details=#{three.id}&detailsType=news_item",
                 title: "This is a nice title"
               }
             ]
    end
  end
end
