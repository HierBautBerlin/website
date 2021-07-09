defmodule Hierbautberlin.GeoData.GeoMapItem do
  defstruct [
    :type,
    :id,
    :title,
    :subtitle,
    :description,
    :positions,
    :newest_date,
    :source,
    :url,
    :participation_open,
    :item
  ]

  def to_json(items) do
    %{
      items:
        Enum.map(items, fn item ->
          %{
            id: item.id,
            type: item.type,
            title: item.title,
            subtitle: item.subtitle,
            description: item.description,
            url: item.url,
            positions:
              Enum.map(item.positions, fn position ->
                result = %{
                  type: position.type,
                  id: position.id
                }

                result =
                  if position.geopoint != nil do
                    Map.put(result, :point, Geo.JSON.encode!(position.geopoint))
                  else
                    result
                  end

                if position.geometry != nil do
                  Map.put(result, :geometry, Geo.JSON.encode!(position.geometry))
                else
                  result
                end
              end)
          }
        end)
    }
    |> Jason.encode!()
  end
end

defmodule Hierbautberlin.GeoData.GeoPosition do
  defstruct [:type, :id, :geopoint, :geometry]
end
