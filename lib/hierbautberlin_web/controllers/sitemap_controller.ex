defmodule HierbautberlinWeb.SitemapController do
  use HierbautberlinWeb, :controller

  alias Hierbautberlin.GeoData

  # Entries older than this are left out: they are still on the map, but hardly
  # ever searched for and would make the sitemap too big to be crawled.
  @months 6
  @cache_seconds 6 * 60 * 60

  def index(conn, _params) do
    conn
    |> put_resp_content_type("application/xml")
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(200, sitemap())
  end

  defp sitemap do
    now = System.monotonic_time(:second)

    case :persistent_term.get({__MODULE__, :sitemap}, nil) do
      {xml, generated_at} when now - generated_at < @cache_seconds ->
        xml

      _ ->
        xml = render_sitemap()
        :persistent_term.put({__MODULE__, :sitemap}, {xml, now})
        xml
    end
  end

  defp render_sitemap do
    pages = [
      {url(~p"/map"), nil},
      {url(~p"/ueber-uns"), nil},
      {url(~p"/impressum"), nil},
      {url(~p"/datenschutz"), nil}
    ]

    since = DateTime.add(DateTime.utc_now(), -30 * @months, :day)

    items =
      Enum.map(GeoData.sitemap_items(since), fn item ->
        {url(~p"/map?#{[details: item.id, detailsType: item.type]}"), item.updated_at}
      end)

    [
      ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
      ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n),
      Enum.map(pages ++ items, &entry/1),
      "</urlset>\n"
    ]
    |> IO.iodata_to_binary()
  end

  defp entry({location, updated_at}) do
    [
      "  <url><loc>",
      escape(location),
      "</loc>",
      if(updated_at, do: ["<lastmod>", DateTime.to_iso8601(updated_at), "</lastmod>"], else: []),
      "</url>\n"
    ]
  end

  defp escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
