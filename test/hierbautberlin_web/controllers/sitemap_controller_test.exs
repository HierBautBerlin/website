defmodule HierbautberlinWeb.SitemapControllerTest do
  use HierbautberlinWeb.ConnCase, async: false

  setup do
    :persistent_term.erase({HierbautberlinWeb.SitemapController, :sitemap})
    :ok
  end

  test "lists the pages and the entries of the last months", %{conn: conn} do
    recent = insert(:geo_item, date_start: DateTime.utc_now())
    old_news = insert(:news_item, published_at: DateTime.add(DateTime.utc_now(), -400, :day))
    hidden = insert(:geo_item, date_start: DateTime.utc_now(), hidden: true)

    conn = get(conn, ~p"/sitemap.xml")
    xml = response(conn, 200)

    assert response_content_type(conn, :xml)
    assert xml =~ ~s(<loc>http://localhost:4002/ueber-uns</loc>)
    assert xml =~ ~s(<loc>http://localhost:4002/map</loc>)
    assert xml =~ "details=#{recent.id}&amp;detailsType=geo_item</loc><lastmod>"
    refute xml =~ "details=#{old_news.id}&amp;detailsType=news_item"
    refute xml =~ "details=#{hidden.id}&amp;detailsType=geo_item"
  end
end
