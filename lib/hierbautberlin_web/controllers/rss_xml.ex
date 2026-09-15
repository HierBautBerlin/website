defmodule HierbautberlinWeb.RSSXML do
  use HierbautberlinWeb, :html

  alias HierbautberlinWeb.MapRouteHelpers

  embed_templates "rss_xml/*"

  def item_link(item) do
    item
    |> then(&MapRouteHelpers.link_to_details(HierbautberlinWeb.Endpoint, &1))
    |> String.replace("&", "&amp;")
  end

  def item_content(item) do
    text =
      if MapRouteHelpers.type_of_item(item) == "geo_item",
        do: item.description,
        else: item.content

    (text || "")
    |> text_to_html()
    |> Phoenix.HTML.safe_to_string()
  end

  def iso_datetime(datetime), do: DateTime.to_iso8601(datetime)
end
