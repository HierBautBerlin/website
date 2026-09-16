defmodule HierbautberlinWeb.MapRouteHelpers do
  use HierbautberlinWeb, :verified_routes

  alias Hierbautberlin.GeoData
  alias Hierbautberlin.GeoData.{GeoItem, GeoPlace, GeoStreet, GeoStreetNumber, NewsItem}

  def route_to_map(
        _conn_or_endpoint,
        map_position,
        map_zoom,
        detail_item \\ nil,
        detail_item_type \\ nil,
        list_collapsed \\ false
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

    route_params = if list_collapsed, do: route_params ++ [list: "collapsed"], else: route_params

    ~p"/map?#{route_params}"
  end

  def link_to_details(_endpoint, item) do
    %{lat: lat, lng: lng} = GeoData.get_point(item)

    if lat && lng do
      url(
        ~p"/map?#{[lat: Float.to_string(lat), lng: Float.to_string(lng), details: item.id, detailsType: type_of_item(item)]}"
      )
    else
      url(~p"/map?#{[details: item.id, detailsType: type_of_item(item)]}")
    end
  end

  @doc """
  The link to share an entry, without the map position: the map centers on the
  entry when it is opened.
  """
  def share_link(item) do
    url(~p"/map?#{[details: item.id, detailsType: type_of_item(item)]}")
  end

  def type_of_item(%GeoItem{}), do: "geo_item"
  def type_of_item(%NewsItem{}), do: "news_item"
  def type_of_item(%GeoStreet{}), do: "geo_street"
  def type_of_item(%GeoStreetNumber{}), do: "geo_street_number"
  def type_of_item(%GeoPlace{}), do: "geo_place"
end
