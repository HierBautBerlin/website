defmodule HierbautberlinWeb.MapLive do
  use HierbautberlinWeb, :live_view

  alias Hierbautberlin.GeoData
  alias Hierbautberlin.Accounts
  alias HierbautberlinWeb.MapRouteHelpers

  @default_title "Karte"
  @lat_default 52.5166309
  @lng_default 13.3781537
  @zoom_default 15

  @impl true
  def mount(params, session, socket) do
    current_user =
      if session["user_token"] do
        Accounts.get_user_by_session_token(session["user_token"])
      else
        nil
      end

    socket =
      assign(socket,
        map_zoom: params["zoom"] || to_string(@zoom_default),
        map_items: [],
        map_position: %{lat: nil, lng: nil},
        current_user: current_user,
        page_title: @default_title,
        show_subscription: nil,
        detail_item: nil,
        detail_item_type: nil,
        page_title: @default_title
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    lat = parse_with_default(params["lat"], @lat_default)
    lng = parse_with_default(params["lng"], @lng_default)
    zoom = parse_with_default(params["zoom"], @zoom_default)

    socket =
      socket
      |> assign(map_zoom: zoom)
      |> update_coordinates(lat, lng)
      |> prefetch_details(params)

    {:noreply, socket}
  end

  @impl true
  def handle_event("updateCoordinates", %{"lat" => lat, "lng" => lng}, socket) do
    socket = update_coordinates(socket, lat, lng)
    socket = assign(socket, %{search_result_visible: false})

    {:noreply,
     push_patch(socket,
       to: route_from_socket(socket),
       replace: true
     )}
  end

  @impl true
  def handle_event("updateZoom", %{"zoom" => zoom}, socket) do
    socket = assign(socket, %{map_zoom: zoom, search_result_visible: false})

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
        page_title: detail_item.title,
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
    socket =
      assign(socket, %{
        page_title: nil,
        detail_item: @default_title
      })

    {:noreply,
     push_patch(socket,
       to: route_from_socket(socket),
       replace: true
     )}
  end

  @impl true
  def handle_event(
        "subscribe",
        %{"subscribe" => "on"},
        %{assigns: %{current_user: current_user, map_position: map_position}} = socket
      ) do
    socket =
      if Accounts.get_subscription(current_user, map_position) == nil do
        {:ok, subscription} = Accounts.subscribe(current_user, map_position)
        assign(socket, :show_subscription, subscription)
      else
        socket
      end

    socket = assign(socket, :subscribed, true)
    {:noreply, socket}
  end

  @impl true
  def handle_event("subscribe", _params, socket) do
    Accounts.unsubscribe(socket.assigns.current_user, socket.assigns.map_position)
    socket = assign(socket, :subscribed, false)
    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"search_field" => %{"query" => query}}, socket) do
    socket = assign(socket, %{search_result: nil, search_text: nil, search_result_visible: false})

    if query |> String.trim() |> String.length() > 0 do
      streets = GeoData.search_street(query)

      if Enum.empty?(streets) do
        {:noreply, socket}
      else
        {:noreply,
         assign(socket, %{search_result: streets, search_text: query, search_result_visible: true})}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("show-results", _, socket) do
    {:noreply, assign(socket, %{search_result_visible: true})}
  end

  @impl true
  def handle_info("close_edit_subscription", socket) do
    {:noreply, assign(socket, :show_subscription, nil)}
  end

  def handle_info({"update_subscription", subscription}, socket) do
    {:noreply, assign(socket, :subscription, subscription)}
  end

  defp update_coordinates(socket, lat, lng) do
    socket =
      if socket.assigns[:map_position] != %{lat: lat, lng: lng} do
        items = GeoData.get_items_near(lat, lng, 100)

        assign(
          socket,
          %{
            map_items: items,
            map_position: %{lat: lat, lng: lng},
            rss_link:
              Routes.rss_path(
                socket,
                :show,
                Float.to_string(lng),
                Float.to_string(lat)
              )
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

  defp prefetch_details(socket, %{"details" => details, "detailsType" => details_type})
       when not is_nil(details) and not is_nil(details_type) do
    {detail_item, detail_item_type} = get_detail_item(details, details_type)

    assign(socket,
      detail_item: detail_item,
      detail_item_type: detail_item_type,
      page_title: detail_item.title
    )
  end

  defp prefetch_details(socket, _params) do
    assign(socket, detail_item: nil, detail_item_type: nil, page_title: @default_title)
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

  defp parse_with_default(string, default) do
    case Float.parse(string || "") do
      :error -> default
      {number, _} -> number
    end
  end
end
