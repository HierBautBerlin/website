defmodule HierbautberlinWeb.MapLive do
  @moduledoc """
  The map page.

  The map itself loads its features as vector tiles from
  `HierbautberlinWeb.MapTileController`. This LiveView only renders the list of
  items next to the map, the search and the detail modals. The client sends one
  debounced `viewport` event after the map was moved.

  The browser remembers the last position (see `assets/js/storage.ts`) and sends
  it as `map_position` connect param. It is used when the URL has no position.
  """
  use HierbautberlinWeb, :live_view

  alias Hierbautberlin.Accounts
  alias Phoenix.LiveView.JS
  alias Hierbautberlin.GeoData
  alias Hierbautberlin.GeoData.MapFeatures
  alias HierbautberlinWeb.{MapComponents, MapRouteHelpers}

  @default_title "Karte"
  @lat_default 52.5166309
  @lng_default 13.3781537
  @zoom_default 15
  # zoom when a shared link to an entry is opened
  @detail_zoom 16
  @detail_types ~w(geo_item news_item geo_street geo_street_number geo_place)
  # Positions from the URL or the browser outside of Berlin and its surroundings
  # (e.g. 0/0 from a broken client) open the default position instead
  @area %{south: 52.0, north: 53.0, west: 12.5, east: 14.5}

  @impl true
  def mount(params, session, socket) do
    current_user =
      if session["user_token"] do
        Accounts.get_user_by_session_token(session["user_token"])
      end

    socket =
      socket
      |> assign(
        current_user: current_user,
        page_title: @default_title,
        map_position: nil,
        map_zoom: @zoom_default,
        map_bounds: nil,
        # {z}/{x}/{y} are placeholders for MapLibre, so this can't be a verified route
        tiles_url: "/tiles/items/#{MapFeatures.version()}/{z}/{x}/{y}.mvt",
        tiles_min_zoom: MapFeatures.min_zoom(),
        subscription: nil,
        show_subscription: nil,
        detail_item: nil,
        detail_item_type: nil,
        detail_shape: nil,
        rss_link: nil,
        search_text: nil,
        search_result: nil,
        search_result_visible: false,
        map_items: [],
        stored_position: stored_position(socket),
        # phones only, in the url so the page is rendered with the list collapsed
        list_collapsed: params["list"] == "collapsed",
        # filters of the list, the hidden sources also apply to the map
        sources: GeoData.list_sources(),
        hidden_sources: [],
        list_query: nil
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket = prefetch_details(socket, params)

    {position, zoom} =
      requested_position(params, socket.assigns.detail_item, socket.assigns.stored_position)

    socket =
      if socket.assigns.map_position == position and socket.assigns.map_zoom == zoom do
        socket
      else
        bounds = MapFeatures.bounds_around(position, zoom)
        update_viewport(socket, position, zoom, bounds)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "viewport",
        %{"center" => %{"lat" => lat, "lng" => lng}, "zoom" => zoom, "bounds" => bounds},
        socket
      ) do
    bounds = %{
      west: to_float(bounds["west"]),
      south: to_float(bounds["south"]),
      east: to_float(bounds["east"]),
      north: to_float(bounds["north"])
    }

    socket =
      socket
      |> update_viewport(
        %{lat: to_float(lat), lng: to_float(lng)},
        zoom |> to_float() |> Float.round(2),
        bounds
      )
      |> assign(:search_result_visible, false)

    {:reply, %{}, push_patch(socket, to: route_from_socket(socket), replace: true)}
  end

  # The list was already collapsed or expanded by list_collapse_toggle/0, this
  # only keeps the state for the url and the next render
  def handle_event("toggle_list", _params, socket) do
    socket = update(socket, :list_collapsed, &(!&1))
    {:noreply, push_patch(socket, to: route_from_socket(socket), replace: true)}
  end

  def handle_event("showDetails", %{"item-id" => item_id, "item-type" => item_type}, socket)
      when item_type in @detail_types do
    socket = assign_detail(socket, get_detail_item(item_id, item_type))

    {:noreply, push_patch(socket, to: route_from_socket(socket), replace: true)}
  end

  def handle_event("showDetails", _params, socket), do: {:noreply, socket}

  def handle_event("hideDetails", _params, socket) do
    socket =
      assign(socket, %{
        page_title: @default_title,
        detail_item: nil,
        detail_item_type: nil,
        detail_shape: nil
      })

    {:noreply, push_patch(socket, to: route_from_socket(socket), replace: true)}
  end

  def handle_event(
        "subscribe",
        %{"subscribe" => "on"},
        %{assigns: %{current_user: current_user, map_position: map_position}} = socket
      ) do
    socket =
      if Accounts.get_subscription(current_user, map_position) == nil do
        {:ok, subscription} = Accounts.subscribe(current_user, map_position)
        assign(socket, show_subscription: subscription, subscription: subscription)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("subscribe", _params, socket) do
    Accounts.unsubscribe(socket.assigns.current_user, socket.assigns.map_position)
    {:noreply, assign(socket, :subscription, nil)}
  end

  def handle_event("search", %{"search_field" => %{"query" => query}}, socket) do
    socket =
      if String.trim(query) == "" do
        assign(socket, search_result: nil, search_text: nil, search_result_visible: false)
      else
        assign(socket,
          search_result: GeoData.search_street(query),
          search_text: query,
          search_result_visible: true
        )
      end

    {:noreply, socket}
  end

  def handle_event("show-results", _, socket) do
    {:noreply, assign(socket, :search_result_visible, socket.assigns.search_result != nil)}
  end

  def handle_event("hide-results", _, socket) do
    {:noreply, assign(socket, :search_result_visible, false)}
  end

  # The map flies to the street on the client, this only closes the results
  def handle_event("select-search-result", %{"name" => name}, socket) do
    {:noreply, assign(socket, search_text: name, search_result_visible: false)}
  end

  # the checkboxes of the sources that are shown, nothing is sent when all are unchecked
  def handle_event("filter-sources", params, socket) do
    shown = params |> Map.get("sources", []) |> MapSet.new()

    hidden =
      socket.assigns.sources
      |> Enum.reject(&(to_string(&1.id) in shown))
      |> Enum.map(& &1.id)

    {:noreply, socket |> assign(:hidden_sources, hidden) |> refresh_list()}
  end

  def handle_event("show-all-sources", _params, socket) do
    {:noreply, socket |> assign(:hidden_sources, []) |> refresh_list()}
  end

  # shorter searches match nearly everything and can't use the index
  @list_query_min_length 3

  def handle_event("search-list", %{"list_search" => %{"query" => query}}, socket) do
    query = String.trim(query)
    query = if String.length(query) < @list_query_min_length, do: nil, else: query

    if query == socket.assigns.list_query do
      {:noreply, socket}
    else
      {:noreply, socket |> assign(:list_query, query) |> refresh_list()}
    end
  end

  def handle_event("clear-list-search", _params, socket) do
    {:noreply, socket |> assign(:list_query, nil) |> refresh_list()}
  end

  def handle_event("close_edit_subscription", _params, socket) do
    {:noreply, assign(socket, :show_subscription, nil)}
  end

  @impl true
  def handle_info("close_edit_subscription", socket) do
    {:noreply, assign(socket, :show_subscription, nil)}
  end

  def handle_info({"update_subscription", subscription}, socket) do
    {:noreply, assign(socket, :subscription, subscription)}
  end

  # The popups of the list toolbar. JS commands keep their state across updates
  # of the LiveView. Opening moves the focus into the popup.
  def list_popup_toggle(id) do
    JS.toggle(to: "##{id}-popup", display: "block")
    |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "##{id}-button")
    |> JS.focus_first(to: "##{id}-popup")
  end

  # Phones only: slides the list down until only the toolbar is left, the map
  # (InteractiveMap) listens to the event and uses the free space
  def list_collapse_toggle do
    %JS{}
    |> list_popup_close("list-sources")
    |> list_popup_close("list-search")
    |> JS.toggle_class("map--item-list-wrapper-collapsed", to: "#map-list-wrapper")
    |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "#list-collapse-button")
    |> JS.dispatch("hierbautberlin:list-toggled", to: "#map-page")
    |> JS.push("toggle_list")
  end

  def list_popup_close(js \\ %JS{}, id) do
    js
    |> JS.hide(to: "##{id}-popup")
    |> JS.set_attribute({"aria-expanded", "false"}, to: "##{id}-button")
  end

  defp refresh_list(%{assigns: %{map_bounds: nil}} = socket), do: socket

  defp refresh_list(socket) do
    %{map_position: position, map_zoom: zoom, map_bounds: bounds} = socket.assigns
    update_viewport(socket, position, zoom, bounds)
  end

  defp update_viewport(socket, position, zoom, bounds) do
    items =
      if zoom >= MapFeatures.min_zoom() do
        MapFeatures.list_items(bounds, position,
          hidden_sources: socket.assigns.hidden_sources,
          query: socket.assigns.list_query
        )
      else
        []
      end

    position_changed? = socket.assigns.map_position != position

    socket
    |> assign(
      map_position: position,
      map_zoom: zoom,
      map_bounds: bounds,
      map_items: items,
      rss_link: ~p"/feed/#{Float.to_string(position.lng)}/#{Float.to_string(position.lat)}"
    )
    |> push_event("map:list-updated", %{})
    |> then(fn socket ->
      if position_changed? do
        assign(
          socket,
          :subscription,
          Accounts.get_subscription(socket.assigns.current_user, position)
        )
      else
        socket
      end
    end)
  end

  defp prefetch_details(socket, %{"details" => details, "detailsType" => details_type})
       when is_binary(details) and details_type in @detail_types do
    if socket.assigns.detail_item_type == details_type and
         to_string(socket.assigns.detail_item && socket.assigns.detail_item.id) == details do
      socket
    else
      assign_detail(socket, get_detail_item(details, details_type))
    end
  end

  defp prefetch_details(socket, _params) do
    assign(socket,
      detail_item: nil,
      detail_item_type: nil,
      detail_shape: nil,
      page_title: @default_title,
      # the position is not part of the canonical url, it would be a different
      # one for every pixel the map was moved
      canonical: url(~p"/map"),
      meta_description: nil,
      ogtags: %{}
    )
  end

  defp assign_detail(socket, {detail_item, detail_item_type}) do
    link = MapRouteHelpers.share_link(detail_item)
    description = description_of(detail_item)

    assign(socket,
      detail_item: detail_item,
      detail_item_type: detail_item_type,
      # lines, polygons and points for the small map in the details
      detail_shape: MapFeatures.details_shape(detail_item),
      page_title: title_of(detail_item),
      # a shared entry is its own page, no matter where the map was
      canonical: link,
      meta_description: description,
      ogtags: %{"og:type" => "article", "og:url" => link}
    )
  end

  @description_length 200

  # The first sentences of the entry for the description meta tag
  defp description_of(item) do
    [Map.get(item, :subtitle), Map.get(item, :description), Map.get(item, :content)]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" ")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> case do
      "" -> nil
      text -> truncate(text, @description_length)
    end
  end

  defp truncate(text, length) do
    if String.length(text) <= length do
      text
    else
      text
      |> String.slice(0, length)
      |> String.replace(~r/\s+\S*$/u, "")
      |> Kernel.<>("…")
    end
  end

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

  def return_news_if_only_one_news_item({%{news_items: [news_item]}, _type}) do
    {news_item, "news_item"}
  end

  def return_news_if_only_one_news_item(value) do
    value
  end

  defp title_of(%{title: title}), do: title
  defp title_of(%{name: name}), do: name
  defp title_of(_item), do: @default_title

  defp route_from_socket(socket) do
    MapRouteHelpers.route_to_map(
      socket,
      socket.assigns.map_position,
      socket.assigns.map_zoom,
      socket.assigns.detail_item,
      socket.assigns.detail_item_type,
      socket.assigns.list_collapsed
    )
  end

  defp subscription_radius(nil), do: "2 KM"

  defp subscription_radius(%{radius: radius}) when radius >= 1000,
    do: "#{trunc(radius / 1000)} KM"

  defp subscription_radius(%{radius: radius}), do: "#{radius} M"

  defp search_results_open?(assigns) do
    assigns.search_result_visible and assigns.search_result != nil
  end

  # "Friedrichshain, Friedrichshain-Kreuzberg"
  defp street_area(street) do
    [street.ortsteil, street.district]
    |> Enum.reject(&blank?/1)
    |> Enum.uniq()
    |> Enum.join(", ")
  end

  defp search_status(nil), do: ""
  defp search_status([]), do: "Keine Straße gefunden"
  defp search_status([_street]), do: "1 Straße gefunden"
  defp search_status(streets), do: "#{length(streets)} Straßen gefunden"

  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value / 1
  defp to_float(value) when is_binary(value), do: parse_with_default(value, 0.0)

  # The position from the URL, otherwise the entry of a shared link
  # (/map?details=…&detailsType=…), otherwise the one the browser remembered,
  # otherwise the center of Berlin
  defp requested_position(params, detail_item, stored) do
    url_position = %{
      lat: parse_with_default(params["lat"], nil),
      lng: parse_with_default(params["lng"], nil)
    }

    detail_position = if detail_item, do: GeoData.get_point(detail_item)

    cond do
      in_area?(url_position) ->
        {url_position, parse_with_default(params["zoom"], @zoom_default)}

      detail_position && in_area?(detail_position) ->
        {detail_position, @detail_zoom}

      stored != nil ->
        {Map.take(stored, [:lat, :lng]), stored.zoom}

      true ->
        {%{lat: @lat_default, lng: @lng_default},
         parse_with_default(params["zoom"], @zoom_default)}
    end
  end

  defp in_area?(%{lat: lat, lng: lng}) when is_number(lat) and is_number(lng) do
    lat >= @area.south and lat <= @area.north and lng >= @area.west and lng <= @area.east
  end

  defp in_area?(_position), do: false

  defp stored_position(socket) do
    with true <- connected?(socket),
         %{"lat" => lat, "lng" => lng} = stored when is_number(lat) and is_number(lng) <-
           get_connect_params(socket)["map_position"],
         true <- in_area?(%{lat: lat, lng: lng}) do
      zoom = stored["zoom"]
      zoom = if is_number(zoom) and zoom >= 0 and zoom <= 22, do: zoom / 1, else: @zoom_default

      %{lat: lat / 1, lng: lng / 1, zoom: zoom}
    else
      _ -> nil
    end
  end

  defp parse_with_default(string, default) when is_binary(string) do
    case Float.parse(string) do
      :error -> default
      {number, _} -> number
    end
  end

  defp parse_with_default(_value, default), do: default
end
