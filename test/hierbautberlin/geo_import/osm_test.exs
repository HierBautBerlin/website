defmodule Hierbautberlin.GeoImport.OSMTest do
  use Hierbautberlin.DataCase, async: false

  alias Hierbautberlin.GeoData.{GeoPlace, GeoStreet, GeoStreetNumber}
  alias Hierbautberlin.GeoImport.OSM

  @fixture "test/support/data/osm/berlin_small.osm"

  setup do
    existing_street =
      insert(:street,
        name: "Teststraße",
        district: "Mitte",
        street_numbers: [build(:street_number, external_id: "101", number: "1")]
      )

    [existing_number] = existing_street.street_numbers

    stale_street = insert(:street, name: "Alte Straße", district: "Mitte", street_numbers: [])

    linked_stale_street =
      insert(:street, name: "Verlinkte Straße", district: "Mitte", street_numbers: [])

    news_item =
      insert(:news_item,
        geo_streets: [existing_street, linked_stale_street],
        geo_street_numbers: [existing_number],
        geo_places: []
      )

    %{
      existing_street: existing_street,
      existing_number: existing_number,
      stale_street: stale_street,
      linked_stale_street: linked_stale_street,
      news_item: news_item
    }
  end

  test "imports streets and addresses and keeps ids and links", context do
    stats = OSM.import(@fixture)

    assert stats.staging.districts == 2
    assert stats.staging.ortsteile == 1

    street = Repo.get!(GeoStreet, context.existing_street.id) |> Repo.preload(:street_numbers)
    assert street.name == "Teststraße"
    assert street.ortsteil == "Moabit"
    assert %Geo.LineString{coordinates: [{13.4, 52.5}, {13.5, 52.5}]} = street.geometry
    assert street.street_number_count == 7

    assert street.street_numbers |> Enum.map(& &1.number) |> Enum.sort() ==
             ["1", "2A", "3", "4", "7", "8", "9"]

    assert Repo.get_by!(GeoStreetNumber, external_id: "105#8").number == "8"

    number_one = Repo.get!(GeoStreetNumber, context.existing_number.id)
    assert number_one.external_id == "101"
    assert number_one.zip == "10115"
    assert number_one.geo_street_id == street.id

    assert Repo.get_by!(GeoStreetNumber, external_id: "way/500#3").number == "3"
    refute Repo.get_by(GeoStreetNumber, external_id: "way/501")

    pankow = Repo.get_by!(GeoStreet, name: "Teststraße", district: "Pankow")
    assert pankow.street_number_count == 1
    assert %Geo.LineString{coordinates: [{13.5, 52.5}, {13.6, 52.5}]} = pankow.geometry

    address_only = Repo.get_by!(GeoStreet, name: "Nur-Adressen-Weg", district: "Mitte")
    assert address_only.geometry == nil
    assert %Geo.Point{coordinates: {13.2, 52.7}} = address_only.geo_point

    refute Repo.get_by(GeoStreet, name: "Parkweg")

    park = Repo.get_by!(GeoPlace, external_id: "osm-park:Mitte:Testpark")
    assert park.type == "Park"
    assert %Geo.MultiPolygon{} = park.geometry

    # squares, lakes and other green spaces are places too
    assert Repo.get_by!(GeoPlace, external_id: "osm-square:Mitte:Testplatz").type == "Square"
    assert Repo.get_by!(GeoPlace, external_id: "osm-water:Mitte:Testsee").type == "Water"
    assert Repo.get_by!(GeoPlace, external_id: "osm-park:Mitte:Testfeld").type == "Park"

    # flowing water is not a place
    refute Repo.get_by(GeoPlace, name: "Testkanal")
    refute Repo.get(GeoStreet, context.stale_street.id)
    assert Repo.get(GeoStreet, context.linked_stale_street.id)

    assert stats.before.street_links == stats.after.street_links
    assert stats.before.street_number_links == stats.after.street_number_links

    news_item = Repo.reload!(context.news_item)
    assert Enum.member?(news_item.geo_points.coordinates, {13.41, 52.5001})
  end

  test "adopts one of several existing parks with the same name and merges their links" do
    unlinked = insert(:place, name: "Testpark", district: "Mitte")
    linked = insert(:place, name: "Testpark", district: "Mitte")
    also_linked = insert(:place, name: "Testpark", district: "Mitte")
    first_news = insert(:news_item, geo_streets: [], geo_street_numbers: [], geo_places: [linked])

    second_news =
      insert(:news_item, geo_streets: [], geo_street_numbers: [], geo_places: [also_linked])

    stats = OSM.import(@fixture)

    assert stats.changes.places_adopted == 1
    assert stats.changes.place_links_moved == 1
    park = Repo.get_by!(GeoPlace, external_id: "osm-park:Mitte:Testpark")
    assert park.id == linked.id
    refute Repo.get(GeoPlace, unlinked.id)
    refute Repo.get(GeoPlace, also_linked.id)

    for news_item <- [first_news, second_news] do
      news_item = news_item |> Repo.reload!() |> Repo.preload(:geo_places, force: true)
      assert Enum.map(news_item.geo_places, & &1.id) == [park.id]
    end
  end

  test "a second import does not change anything" do
    OSM.import(@fixture)

    # Loading the file again would wait for locks of the test transaction,
    # the SQL part is what matters here.
    OSM.build_staging_tables("Berlin")
    changes = OSM.upsert()

    assert changes == %{
             places_upserted: 0,
             places_adopted: 0,
             place_links_moved: 0,
             places_deleted: 0,
             streets_upserted: 0,
             streets_deleted: 0,
             numbers_upserted: 0,
             numbers_deleted: 0,
             news_items_updated: 0
           }
  end
end
