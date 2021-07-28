defmodule HierbautberlinWeb.RSSController do
  use HierbautberlinWeb, :controller

  alias Hierbautberlin.GeoData

  def show(conn, params) do
    locations = [
      %{
        location: {String.to_float(params["lat"]), String.to_float(params["lng"])},
        radius: 2000
      }
    ]

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
    |> put_root_layout(false)
    |> put_resp_content_type("application/rss+xml")
    |> render("show.xml", items: items)
  end
end
