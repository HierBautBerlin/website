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

    current_user =
      if session["user_token"] do
        Accounts.get_user_by_session_token(session["user_token"])
      else
        nil
      end

    socket =
      assign(socket,
        map_zoom: params["zoom"] || to_string(@zoom_default),
        current_user: current_user,
        page_title: "Karte"
      )

    if connected?(socket) do
      {:ok, update_coordinates(socket, coordinates[:lat], coordinates[:lng])}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    lat = parse_with_default(params["lat"], @lat_default)
    lng = parse_with_default(params["lng"], @lng_default)
    zoom = parse_with_default(params["zoom"], @zoom_default)

    socket = assign(socket, map_zoom: zoom)
    socket = update_coordinates(socket, lat, lng)

    socket =
      if params["details"] do
        {detail_item, detail_item_type} =
          get_detail_item(params["details"], params["detailsType"])

        assign(socket, detail_item: detail_item, detail_item_type: detail_item_type)
      else
        assign(socket, detail_item: nil, detail_item_type: nil)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("updateCoordinates", %{"lat" => lat, "lng" => lng}, socket) do
    socket = update_coordinates(socket, lat, lng)

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

  def handle_event("showDetails", %{"item-id" => item_id, "item-type" => item_type}, socket) do
    {detail_item, detail_item_type} = get_detail_item(item_id, item_type)

    socket =
      assign(socket, %{
        detail_item: detail_item,
        detail_item_type: detail_item_type
      })

    {:noreply,
     push_patch(socket,
       to: route_from_socket(socket),
       replace: true
     )}
  end

  def handle_event("hideDetails", _params, socket) do
    socket = assign(socket, :detail_item, nil)

    {:noreply,
     push_patch(socket,
       to: route_from_socket(socket),
       replace: true
     )}
  end

  @impl true
  def handle_event("subscribe", %{"subscribe" => "on"}, socket) do
    if Accounts.get_subscription(socket.assigns.current_user, socket.assigns.map_position) == nil do
      Accounts.subscribe(socket.assigns.current_user, socket.assigns.map_position)
    end

    socket = assign(socket, :subscribed, true)
    {:noreply, socket}
  end

  def handle_event("subscribe", _params, socket) do
    Accounts.unsubscribe(socket.assigns.current_user, socket.assigns.map_position)
    socket = assign(socket, :subscribed, false)
    {:noreply, socket}
  end

  defp update_coordinates(socket, lat, lng) do
    socket =
      if socket.assigns[:map_position] != %{lat: lat, lng: lng} do
        items = GeoData.get_items_near(lat, lng, 30)

        assign(
          socket,
          %{
            map_items: items,
            map_position: %{lat: lat, lng: lng}
          }
        )
      else
        socket
      end

    assign(
      socket,
      :subscription,
      Accounts.get_subscription(socket.assigns.current_user, %{lat: lat, lng: lng})
    )
  end

  defp get_detail_item(item_id, item_type)

  defp get_detail_item(item_id, "geo_item") do
    {GeoData.get_geo_item!(item_id), "geo_item"}
  end

  defp get_detail_item(item_id, "news_item") do
    {GeoData.get_news_item!(item_id), "news_item"}
  end

  defp get_detail_item(item_id, "geo_street") do
    {item_id
     |> GeoData.get_geo_street!()
     |> GeoData.with_news(), "geo_street"}
    |> return_news_if_only_one_news_item()
  end

  defp get_detail_item(item_id, "geo_street_number") do
    {item_id
     |> GeoData.get_geo_street_number!()
     |> GeoData.with_geo_street()
     |> GeoData.with_news(), "geo_street_number"}
    |> return_news_if_only_one_news_item()
  end

  defp get_detail_item(item_id, "geo_place") do
    {item_id
     |> GeoData.get_geo_place!()
     |> GeoData.with_news(), "geo_place"}
    |> return_news_if_only_one_news_item()
  end

  def return_news_if_only_one_news_item(value)

  def return_news_if_only_one_news_item({%{news_items: [news_item]}, _type}) do
    {news_item, "news_item"}
  end

  def return_news_if_only_one_news_item(value) do
    value
  end

  defp route_from_socket(socket) do
    MapRouteHelpers.route_to_map(
      socket,
      socket.assigns.map_position,
      socket.assigns.map_zoom,
      socket.assigns.detail_item,
      socket.assigns.detail_item_type
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
