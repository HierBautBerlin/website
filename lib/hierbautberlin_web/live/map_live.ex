defmodule HierbautberlinWeb.MapLive do
  use HierbautberlinWeb, :live_view

  alias Hierbautberlin.GeoData
  alias HierbautberlinWeb.MapRouteHelpers

  @lat_default 52.5166309
  @lng_default 13.3781537
  @zoom_default 15

  @impl true
  def mount(params, _session, socket) do
    coordinates = calculate_coordinates(params)

    items = GeoData.get_items_near(coordinates[:lat], coordinates[:lng], 100)

    {:ok,
     assign(socket,
       mapPosition: coordinates,
       mapZoom: params["zoom"] || to_string(@zoom_default),
       mapItems: items
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    lat = parse_with_default(params["lat"], @lat_default)
    lng = parse_with_default(params["lng"], @lng_default)
    zoom = parse_with_default(params["zoom"], @zoom_default)

    items = GeoData.get_items_near(lat, lng, 100)

    socket =
      assign(socket,
        mapPosition: %{lat: lat, lng: lng},
        mapItems: items,
        mapZoom: zoom,
        detailItem: nil
      )

    socket =
      if params["details"] do
        assign(socket, detailItem: GeoData.get_geo_item!(params["details"]))
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("updateCoordinates", %{"lat" => lat, "lng" => lng}, socket) do
    socket = assign(socket, :mapPosition, %{lat: lat, lng: lng})

    {:noreply,
     push_patch(socket,
       to: route_from_socket(socket),
       replace: true
     )}
  end

  @impl true
  def handle_event("updateZoom", %{"zoom" => zoom}, socket) do
    socket = assign(socket, :mapZoom, zoom)

    {:noreply,
     push_patch(socket,
       to: route_from_socket(socket),
       replace: true
     )}
  end

  def handle_event("showDetails", %{"item-id" => item_id}, socket) do
    socket = assign(socket, detailItem: GeoData.get_geo_item!(item_id))

    {:noreply,
     push_patch(socket,
       to: route_from_socket(socket),
       replace: true
     )}
  end

  def handle_event("hideDetails", _params, socket) do
    socket = assign(socket, :detailItem, nil)

    {:noreply,
     push_patch(socket,
       to: route_from_socket(socket),
       replace: true
     )}
  end

  defp route_from_socket(socket) do
    MapRouteHelpers.route_to_map(
      socket,
      socket.assigns.mapPosition,
      socket.assigns.mapZoom,
      socket.assigns.detailItem
    )
  end

  defp calculate_coordinates(params) do
    %{
      lat: parse_with_default(params["lat"], @lat_default),
      lng: parse_with_default(params["lng"], @lng_default)
    }
  end

  defp parse_with_default(string, default) do
    case Float.parse(string || "") do
      :error -> default
      {number, _} -> number
    end
  end
end
