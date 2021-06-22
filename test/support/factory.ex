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

  def geo_item_factory do
    %Hierbautberlin.GeoData.GeoItem{
      title: "This is a nice item",
      description: "This is a description",
      source: fn -> build(:source) end
    }
  end
end
