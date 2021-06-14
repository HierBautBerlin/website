defmodule HierbautberlinWeb.MapRouteHelpers do
  alias HierbautberlinWeb.Router.Helpers, as: Routes

  def route_to_map(socket, map_position, map_zoom, detailItem) do
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

    Routes.map_path(socket, :index, route_params)
  end
end
