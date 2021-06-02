defmodule HierbautberlinWeb.MapLive do
  use HierbautberlinWeb, :live_view

  alias Hierbautberlin.GeoData

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
        mapZoom: zoom
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("updateCoordinates", %{"lat" => lat, "lng" => lng}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         Routes.map_path(socket, :index,
           lat: to_string(lat),
           lng: to_string(lng),
           zoom: to_string(socket.assigns.mapZoom)
         ),
       replace: true
     )}
  end

  @impl true
  def handle_event("updateZoom", %{"zoom" => zoom}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         Routes.map_path(socket, :index,
           lat: to_string(socket.assigns.mapPosition.lat),
           lng: to_string(socket.assigns.mapPosition.lng),
           zoom: to_string(zoom)
         ),
       replace: true
     )}
  end

  def calculate_coordinates(params) do
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
