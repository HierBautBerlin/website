defmodule HierbautberlinWeb.MapRouteHelpers do
  alias HierbautberlinWeb.Router.Helpers, as: Routes
  alias Hierbautberlin.GeoData

  def route_to_map(conn_or_endpoint, map_position, map_zoom, detailItem \\ nil) do
    route_params = [
      lat: to_string(map_position.lat),
      lng: to_string(map_position.lng),
      zoom: to_string(map_zoom)
    ]

    route_params =
      if detailItem do
        route_params ++
          [
            details: to_string(detailItem.id)
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
        details: item.id
      )
    else
      Routes.map_url(endpoint, :index, details: item.id)
    end
  end
end
