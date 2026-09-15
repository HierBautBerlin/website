defmodule Hierbautberlin.Importer.KmlParser do
  @moduledoc """
  Minimal KML parser that extracts the geometries of all placemarks.

  Only the geometry types used by our data sources are supported:
  `Point`, `LineString`, `Polygon` (outer boundary only) and `MultiGeometry`.
  """

  import SweetXml, only: [xpath: 2, sigil_x: 2]

  require Record

  Record.defrecordp(
    :xml_element,
    :xmlElement,
    Record.extract(:xmlElement, from_lib: "xmerl/include/xmerl.hrl")
  )

  @geometry_tags [~c"Point", ~c"LineString", ~c"Polygon", ~c"MultiGeometry"]

  def parse(kml) when kml in [nil, ""], do: []

  def parse(kml) do
    kml
    |> SweetXml.parse(dtd: :none, quiet: true)
    |> xpath(~x"//*[local-name()='Placemark']"l)
    |> Enum.map(fn placemark ->
      %{geoms: placemark |> geometry_children() |> Enum.map(&element_to_geo/1)}
    end)
  end

  def extract_point(kml) do
    kml
    |> Enum.find(fn item -> point?(List.first(item.geoms)) end)
    |> first_geometry()
  end

  def extract_polygon(kml) do
    kml
    |> Enum.find(fn item -> !point?(List.first(item.geoms)) end)
    |> first_geometry()
  end

  defp first_geometry(%{geoms: [geom | _]}), do: geom
  defp first_geometry(_), do: nil

  defp point?(%Geo.Point{}), do: true
  defp point?(_), do: false

  defp geometry_children(element) do
    element
    |> child_elements()
    |> Enum.filter(&(local_name(&1) in @geometry_tags))
  end

  defp element_to_geo(element) do
    case local_name(element) do
      ~c"Point" ->
        [coordinate | _] = coordinates_of(element)
        %Geo.Point{coordinates: coordinate, srid: 4326}

      ~c"LineString" ->
        %Geo.LineString{coordinates: coordinates_of(element), srid: 4326}

      ~c"Polygon" ->
        outer = xpath(element, ~x"./*[local-name()='outerBoundaryIs']"e)
        %Geo.Polygon{coordinates: [coordinates_of(outer)], srid: 4326}

      ~c"MultiGeometry" ->
        case element |> geometry_children() |> Enum.map(&element_to_geo/1) do
          [single] -> single
          geometries -> %Geo.GeometryCollection{geometries: geometries, srid: 4326}
        end
    end
  end

  defp coordinates_of(element) do
    element
    |> xpath(~x".//*[local-name()='coordinates']/text()"s)
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(fn tuple ->
      [x, y | _altitude] = String.split(tuple, ",")
      {parse_float(x), parse_float(y)}
    end)
  end

  defp parse_float(value) do
    {number, _} = Float.parse(value)
    number
  end

  defp child_elements(element) do
    element
    |> xml_element(:content)
    |> Enum.filter(&Record.is_record(&1, :xmlElement))
  end

  defp local_name(element) do
    case xml_element(element, :nsinfo) do
      {_prefix, local} -> local
      _ -> Atom.to_charlist(xml_element(element, :name))
    end
  end
end
