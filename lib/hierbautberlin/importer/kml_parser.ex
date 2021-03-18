defmodule Hierbautberlin.Importer.KmlParser do
  def parse(kml) do
    if kml == nil || String.length(kml) == 0 do
      []
    else
      String.splitter(kml, "\n")
      |> Exkml.stream!()
      |> Enum.into([])
    end
  end

  def extract_point(kml) do
    Enum.find(kml, fn item ->
      geodata = item.geoms |> List.first()
      is_point(geodata)
    end)
    |> item_to_geo()
  end

  def extract_polygon(kml) do
    Enum.find(kml, fn item ->
      geodata = item.geoms |> List.first()
      !is_point(geodata)
    end)
    |> item_to_geo()
  end

  defp item_to_geo(%Exkml.Placemark{} = placemark) do
    placemark.geoms
    |> List.first()
    |> kml_to_geo()
  end

  defp item_to_geo(_) do
    nil
  end

  defp is_point(%Exkml.Point{}) do
    true
  end

  defp is_point(_) do
    false
  end

  defp kml_to_geo(%Exkml.Point{} = point) do
    %Geo.Point{coordinates: {point.y, point.x}, srid: 3857}
  end

  defp kml_to_geo(%Exkml.Line{} = line) do
    %Geo.LineString{
      coordinates:
        Enum.map(line.points, fn item ->
          {item.y, item.x}
        end),
      srid: 3857
    }
  end

  defp kml_to_geo(%Exkml.Multigeometry{} = multi) do
    if length(multi.geoms) > 1 do
      %Geo.GeometryCollection{
        geometries:
          Enum.map(multi.geoms, fn item ->
            kml_to_geo(item)
          end),
        srid: 3857
      }
    else
      kml_to_geo(List.first(multi.geoms))
    end
  end

  defp kml_to_geo(%Exkml.Polygon{} = polygon) do
    %Geo.Polygon{
      coordinates: [
        Enum.map(polygon.outer_boundary.points, fn item ->
          {item.y, item.x}
        end)
      ],
      srid: 3857
    }
  end
end
