defmodule HierbautberlinWeb.MapLive do
  use HierbautberlinWeb, :live_view

  alias Hierbautberlin.GeoData
  alias Hierbautberlin.Accounts
  alias HierbautberlinWeb.MapRouteHelpers

  @lat_default 52.5166309
  @lng_default 13.3781537
  @zoom_default 15

  @impl true
  def mount(params, session, socket) do
    coordinates = calculate_coordinates(params)

    items = GeoData.get_items_near(coordinates[:lat], coordinates[:lng], 100)

    current_user =
      if session["user_token"] do
        Accounts.get_user_by_session_token(session["user_token"])
      else
        nil
      end

    {:ok,
     assign(socket,
       map_position: coordinates,
       map_zoom: params["zoom"] || to_string(@zoom_default),
       map_items: items,
       current_user: current_user,
       subscription: Accounts.get_subscription(current_user, coordinates),
       page_title: "Karte"
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
        map_position: %{lat: lat, lng: lng},
        map_items: items,
        map_zoom: zoom,
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
    socket = assign(socket, :map_position, %{lat: lat, lng: lng})

    socket =
      assign(
        socket,
        :subscription,
        Accounts.get_subscription(socket.assigns.current_user, %{lat: lat, lng: lng})
      )

    {:noreply,
     push_patch(socket,
       to: route_from_socket(socket),
       replace: true
     )}
  end

  @impl true
  def handle_event("updateZoom", %{"zoom" => zoom}, socket) do
    socket = assign(socket, :map_zoom, zoom)

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

  @impl true
  def handle_event("subscribe", %{"subscribe" => "on"}, socket) do
    Accounts.subscribe(socket.assigns.current_user, socket.assigns.map_position)
    socket = assign(socket, :subscribed, true)
    {:noreply, socket}
  end

  def handle_event("subscribe", _params, socket) do
    Accounts.unsubscribe(socket.assigns.current_user, socket.assigns.map_position)
    socket = assign(socket, :subscribed, false)
    {:noreply, socket}
  end

  defp route_from_socket(socket) do
    MapRouteHelpers.route_to_map(
      socket,
      socket.assigns.map_position,
      socket.assigns.map_zoom,
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
