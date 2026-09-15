defmodule HierbautberlinWeb.RSSController do
  use HierbautberlinWeb, :controller

  alias Hierbautberlin.GeoData

  def show(conn, params) do
    with {lat, ""} <- Float.parse(params["lat"] || ""),
         {lng, ""} <- Float.parse(params["lng"] || "") do
      render_feed(conn, params, [%{location: {lat, lng}, radius: 2000}])
    else
      _ -> send_resp(conn, 400, "invalid coordinates")
    end
  end

  defp render_feed(conn, params, locations) do
    items =
      GeoData.get_geo_items_for_locations_since(
        locations,
        Timex.shift(Timex.now(), weeks: -4)
      ) ++
        GeoData.get_news_items_for_locations_since(
          locations,
          Timex.shift(Timex.now(), weeks: -4)
        )

    conn
    |> put_format("xml")
    |> put_root_layout(false)
    |> put_view(xml: HierbautberlinWeb.RSSXML)
    |> put_resp_content_type("application/rss+xml")
    |> render(:show, items: items, lat: params["lat"], lng: params["lng"])
  end
end
