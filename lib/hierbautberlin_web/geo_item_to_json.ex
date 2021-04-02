defmodule HierbautberlinWeb.GeoItemToJson do
  def geo_item_to_json(geo_items) do
    %{
      items:
        Enum.map(geo_items, fn item ->
          result = %{
            id: item.id,
            title: item.title,
            subtitle: item.subtitle,
            description: item.description,
            url: item.url,
            state: item.state,
            additional_link: item.additional_link,
            additional_link_name: item.additional_link_name
          }

          result =
            if item.geo_point != nil do
              Map.put(result, :point, Geo.JSON.encode!(item.geo_point))
            else
              result
            end

          if item.geo_geometry != nil do
            Map.put(result, :geometry, Geo.JSON.encode!(item.geo_geometry))
          else
            result
          end
        end)
    }
    |> Jason.encode!()
  end
end
