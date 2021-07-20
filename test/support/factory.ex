defmodule Hierbautberlin.Factory do
  use ExMachina.Ecto, repo: Hierbautberlin.Repo

  def source_factory do
    %Hierbautberlin.GeoData.Source{
      short_name: sequence(:source_name, &"TEST-#{&1}"),
      name: "City Source",
      url: "https://city.example.com",
      copyright: "Example"
    }
  end

  def street_factory do
    %Hierbautberlin.GeoData.GeoStreet{
      city: "Berlin",
      district: "Friedrichshain",
      geo_point: %Geo.Point{
        coordinates: {13.0, 52.0},
        properties: %{},
        srid: 4326
      },
      street_numbers: fn ->
        [
          build(:street_number, number: "1"),
          build(:street_number, number: "2A")
        ]
      end
    }
  end

  def street_number_factory do
    %Hierbautberlin.GeoData.GeoStreetNumber{
      external_id: sequence(:number_external_id, &"ID-#{&1}"),
      number: "1",
      zip: "10249",
      geo_point: %Geo.Point{
        coordinates: {13.0, 52.0},
        properties: %{},
        srid: 4326
      }
    }
  end

  def street_number_with_street_factory do
    struct!(
      street_number_factory(),
      %{
        geo_street: fn -> build(:street, street_numbers: []) end
      }
    )
  end

  def geo_item_factory do
    %Hierbautberlin.GeoData.GeoItem{
      title: "This is a nice item",
      description: "This is a description",
      source: fn -> build(:source) end
    }
  end

  def place_factory do
    %Hierbautberlin.GeoData.GeoPlace{
      external_id: sequence(:place_external_id, &"ID-#{&1}"),
      name: "Malcom-X-Platz",
      district: "Friedrichshain",
      city: "Berlin",
      type: "Park",
      geo_point: %Geo.Point{
        coordinates: {13.2679, 52.51},
        properties: %{},
        srid: 4326
      },
      geometry: %Geo.Polygon{
        coordinates: [[{13.0, 52.0}, {13.1, 52.1}, {13.1, 52.0}, {13.0, 52.0}]],
        properties: %{},
        srid: 4326
      }
    }
  end

  def news_item_factory do
    %Hierbautberlin.GeoData.NewsItem{
      external_id: sequence(:news_item_external_id, &"ID-#{&1}"),
      title: "This is a nice title",
      content: "This is a nice content",
      url: "https://www.example.com",
      source: fn -> build(:source) end,
      published_at: Timex.now(),
      geo_streets: fn -> [build(:street)] end,
      geo_street_numbers: fn -> [build(:street_number_with_street)] end,
      geo_places: fn -> [build(:place)] end
    }
    |> evaluate_lazy_attributes()
    |> Hierbautberlin.GeoData.NewsItem.update_cached_geometries()
    |> Ecto.Changeset.apply_changes()
  end
end
