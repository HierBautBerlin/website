defmodule HierbautberlinWeb.MapRouteHelpers do
  alias HierbautberlinWeb.Router.Helpers, as: Routes

  def route_to_map(socket, mapPosition, mapZoom, detailItem) do
    route_params = [
      lat: to_string(mapPosition.lat),
      lng: to_string(mapPosition.lng),
      zoom: to_string(mapZoom)
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

    Routes.map_path(socket, :index, route_params)
  end
end
