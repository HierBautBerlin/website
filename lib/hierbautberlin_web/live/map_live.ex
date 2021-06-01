defmodule HierbautberlinWeb.MapLive do
  use HierbautberlinWeb, :live_view

  alias Hierbautberlin.GeoData

  @impl true
  def mount(params, _session, socket) do
    coordinates = calculate_coordinates(params)

    items = GeoData.get_items_near(coordinates[:lat], coordinates[:lng], 100)

    {:ok,
     assign(socket,
       mapPosition: coordinates,
       mapItems: items
     )}
  end

  @impl true
  def handle_event("updateCoordinates", %{"lat" => lat, "lng" => lng}, socket) do
    items = GeoData.get_items_near(lat, lng, 100)

    socket =
      assign(socket,
        mapPosition: %{lat: lat, lng: lng},
        mapItems: items
      )

    {:noreply, socket}
  end

  def calculate_coordinates(params) do
    %{
      lat: parse_with_default(params["lat"], 52.5166309),
      lng: parse_with_default(params["lng"], 13.3781537)
    }
  end

  defp parse_with_default(string, default) do
    case Float.parse(string || "") do
      :error -> default
      {number, _} -> number
    end
  end
end
