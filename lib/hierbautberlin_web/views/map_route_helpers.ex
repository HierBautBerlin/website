defmodule HierbautberlinWeb.MapRouteHelpers do
  alias HierbautberlinWeb.Router.Helpers, as: Routes
  alias Hierbautberlin.GeoData
  alias Hierbautberlin.GeoData.{GeoItem, NewsItem}

  def route_to_map(
        conn_or_endpoint,
        map_position,
        map_zoom,
        detail_item \\ nil,
        detail_item_type \\ nil
      ) do
    route_params = [
      lat: to_string(map_position.lat),
      lng: to_string(map_position.lng),
      zoom: to_string(map_zoom)
    ]

    route_params =
      if detail_item do
        route_params ++
          [
            details: to_string(detail_item.id),
            detailsType: to_string(detail_item_type)
          ]
      else
        route_params
      end

    Routes.map_path(conn_or_endpoint, :index, route_params)
  end

  def link_to_details(endpoint, item) do
    %{lat: lat, lng: lng} = GeoData.get_point(item)

    if lat && lng do
      Routes.map_url(endpoint, :index,
        lat: Float.to_string(lat),
        lng: Float.to_string(lng),
        details: item.id,
        detailsType: type_of_item(item)
      )
    else
      Routes.map_url(endpoint, :index, details: item.id, detailsType: type_of_item(item))
    end
  end

  def type_of_item(%GeoItem{}) do
    "geo_item"
  end

  def type_of_item(%NewsItem{}) do
    "news_item"
  end
end
