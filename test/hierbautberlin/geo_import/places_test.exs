defmodule Hierbautberlin.GeoImport.PlacesTest do
  use Hierbautberlin.DataCase, async: false

  alias Hierbautberlin.GeoData.GeoPlace
  alias Hierbautberlin.GeoImport.Places

  defp polygon(lng, lat) do
    %{
      "type" => "MultiPolygon",
      "coordinates" => [
        [[[lng, lat], [lng + 0.01, lat], [lng + 0.01, lat + 0.01], [lng, lat + 0.01], [lng, lat]]]
      ]
    }
  end

  defp fake_fetch("lor_2021", _layer) do
    %{
      "features" => [
        %{
          "properties" => %{
            "plr_id" => "01100101",
            "plr_name" => "Stülerstraße",
            "bez" => "01 - Mitte"
          },
          "geometry" => polygon(13.34, 52.50)
        }
      ]
    }
  end

  defp fake_fetch("schulen", _layer) do
    %{
      "features" => [
        %{
          "properties" => %{"bsn" => "01B01", "schulname" => "OSZ Banken ", "bezirk" => "Mitte"},
          "geometry" => %{"type" => "Point", "coordinates" => [13.35, 52.52]}
        }
      ]
    }
  end

  test "imports LORs and schools and keeps existing places" do
    old_lor =
      insert(:place,
        external_id: "Stülerstraße",
        name: "Stülerstraße",
        district: "Mitte",
        type: "LOR"
      )

    stale_lor = insert(:place, name: "Weg", type: "LOR", district: "Mitte")
    linked_lor = insert(:place, name: "Verlinkt", type: "LOR", district: "Mitte")
    insert(:news_item, geo_streets: [], geo_street_numbers: [], geo_places: [linked_lor])

    stats = Places.import(Places.types(), &fake_fetch/2)

    assert stats["LOR"] == %{imported: 1, adopted: 1, upserted: 1, deleted: 1}

    lor = Repo.get!(GeoPlace, old_lor.id)
    assert lor.external_id == "lor:01100101"
    assert lor.name == "Stülerstraße"
    assert lor.district == "Mitte"
    assert %Geo.MultiPolygon{} = lor.geometry
    assert %Geo.Point{} = lor.geo_point

    refute Repo.get(GeoPlace, stale_lor.id)
    assert Repo.get(GeoPlace, linked_lor.id)

    school = Repo.get_by!(GeoPlace, external_id: "01B01")
    assert school.name == "OSZ Banken"
    assert school.geometry == nil
    assert %Geo.Point{coordinates: {13.35, 52.52}} = school.geo_point

    second_run = Places.import(Places.types(), &fake_fetch/2)

    assert Enum.all?(second_run, fn {_type, stats} ->
             stats.upserted == 0 and stats.deleted == 0
           end)
  end
end
