defmodule Mix.Tasks.ImportStreets do
  use Mix.Task

  alias Hierbautberlin.Repo
  alias Hierbautberlin.GeoData.GeoStreet
  alias Hierbautberlin.GeoData.GeoStreetNumber
  alias Hierbautberlin.Services.Berlin

  import Hierbautberlin.Services.Blank

  @shortdoc "Imports street data into the database"
  def run(_) do
    Ecto.Migrator.with_repo(Hierbautberlin.Repo, fn _repo ->
      IO.puts("Importing to database")

      File.stream!("data/street_with_number.csv")
      |> CSV.decode!(separator: ?;)
      |> Stream.map(fn row ->
        [external_id, name, number, zip, city, local_center, lng, lat] = row

        %{
          external_id: external_id,
          name: name,
          number: number,
          zip: zip,
          city: city,
          district: Berlin.district_for_local_center(local_center),
          geo_point: %Geo.Point{
            coordinates: {String.to_float(lng), String.to_float(lat)},
            srid: 4326
          },
          inserted_at: DateTime.truncate(DateTime.now!("Etc/UTC"), :second),
          updated_at: DateTime.truncate(DateTime.now!("Etc/UTC"), :second)
        }
      end)
      |> Stream.filter(fn item ->
        # fix this later and try to figure out the zip and district based
        # on the geo coordinates, see #178 for details
        !(is_blank?(item.zip) || is_blank?(item.district) || is_blank?(item.number))
      end)
      |> Enum.reduce(%{}, &row_to_map/2)
      |> Enum.each(&insert_streets/1)
    end)
  end

  defp row_to_map(item, list) do
    if list_item = Map.get(list, "#{item.district}-#{item.name}") do
      numbers = Map.get(list_item, :numbers)

      list_item =
        Map.put(
          list_item,
          :numbers,
          numbers ++ [item_to_number(item)]
        )

      Map.put(list, "#{item.district}-#{item.name}", list_item)
    else
      numbers = [item_to_number(item)]

      Map.put(list, "#{item.district}-#{item.name}", %{
        name: item.name,
        city: item.city,
        district: item.district,
        numbers: numbers
      })
    end
  end

  defp insert_streets({_key, item}) do
    numbers =
      item.numbers
      |> Enum.sort_by(fn item ->
        case Integer.parse(item.number) do
          {number, _} -> number
          :error -> nil
        end
      end)

    middle = Enum.at(numbers, div(length(numbers), 2))

    coordinates =
      Enum.map(numbers, fn item ->
        item.geo_point.coordinates
      end)

    geometry =
      if Enum.count_until(numbers, 2) > 1 do
        %Geo.LineString{
          coordinates: coordinates,
          srid: 4326
        }
      else
        Enum.at(numbers, 0).geo_point
      end

    {:ok, struct} =
      Repo.insert(%GeoStreet{
        name: item.name,
        city: item.city,
        district: item.district,
        geometry: geometry,
        geo_point: middle.geo_point
      })

    numbers =
      numbers
      |> Enum.map(fn item ->
        Map.merge(%{geo_street_id: struct.id}, item)
      end)

    Repo.insert_all(GeoStreetNumber, numbers)
  end

  defp item_to_number(item) do
    %{
      external_id: item.external_id,
      number: item.number |> String.upcase() |> String.replace(" ", ""),
      zip: item.zip,
      geo_point: item.geo_point
    }
  end
end
