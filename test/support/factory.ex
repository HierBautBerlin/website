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
        coordinates: {13, 52},
        properties: %{},
        srid: 4326
      },
      street_numbers: [build(:street_number, number: "1"), build(:street_number, number: "2A")]
    }
  end

  def street_number_factory do
    %Hierbautberlin.GeoData.GeoStreetNumber{
      external_id: sequence(:number_external_id, &"ID-#{&1}"),
      number: "1",
      zip: "10249",
      geo_point: %Geo.Point{
        coordinates: {13, 52},
        properties: %{},
        srid: 4326
      }
    }
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
      type: "Park"
    }
  end
end
