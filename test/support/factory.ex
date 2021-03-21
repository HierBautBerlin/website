defmodule Hierbautberlin.Factory do
  use ExMachina.Ecto, repo: Hierbautberlin.Repo

  def source_factory do
    %Hierbautberlin.GeoData.Source{
      short_name: "TEST",
      name: "City Source",
      url: "https://city.example.com",
      copyright: "Example"
    }
  end
end
