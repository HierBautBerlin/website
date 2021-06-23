defmodule Hierbautberlin.GeoDataTest do
  use Hierbautberlin.DataCase

  alias Hierbautberlin.GeoData

  describe "get_source/1" do
    test "gets a source by it's id" do
      data = insert(:source)

      geo_data = GeoData.get_source!(data.id)
      assert geo_data.short_name =~ ~r/^TEST-/
      assert geo_data.name == "City Source"
      assert geo_data.url == "https://city.example.com"
      assert geo_data.copyright == "Example"
    end

    test "raises no result if id is not found" do
      assert_raise Ecto.NoResultsError, fn -> GeoData.get_source!(2_131_231) end
    end
  end

  describe "upsert_source/1" do
    test "creates and updates a source" do
      {:ok, insert} =
        GeoData.upsert_source(%{
          short_name: "TEST",
          name: "City Source",
          url: "https://city.example.com",
          copyright: "Example"
        })

      assert insert.short_name == "TEST"
      assert insert.name == "City Source"
      assert insert.url == "https://city.example.com"
      assert insert.copyright == "Example"

      {:ok, upsert} =
        GeoData.upsert_source(%{
          short_name: "TEST",
          name: "Village Source",
          url: "https://village.example.com",
          copyright: "MIT"
        })

      assert insert.id == upsert.id

      geo_data = GeoData.get_source!(upsert.id)
      assert geo_data.short_name == "TEST"
      assert geo_data.name == "Village Source"
      assert geo_data.url == "https://village.example.com"
      assert geo_data.copyright == "MIT"
    end
  end

  describe "get_geo_item!/1" do
    test "it returns a geo item" do
      source = insert(:source)

      {:ok, item} =
        GeoData.create_geo_item(%{
          source_id: source.id,
          external_id: "12354",
          title: "Example Item"
        })

      geo_item = GeoData.get_geo_item!(item.id)

      assert geo_item.id == item.id
      assert geo_item.source_id == source.id
      assert geo_item.external_id == "12354"
      assert geo_item.title == "Example Item"
    end
  end

  describe "change_geo_item!/1" do
    test "it returns a GeoItem changeset" do
      source = insert(:source)

      {:ok, item} =
        GeoData.create_geo_item(%{
          source_id: source.id,
          external_id: "12354",
          title: "Example Item"
        })

      assert %Ecto.Changeset{} = GeoData.change_geo_item(item)
    end
  end

  describe "upsert_geo_item/1" do
    test "it creates and updates a GeoItem" do
      source = insert(:source)

      {:ok, item} =
        GeoData.upsert_geo_item(%{
          source_id: source.id,
          external_id: "12354",
          title: "Example Item",
          subtitle: "Hm..."
        })

      geo_item = GeoData.get_geo_item!(item.id)

      assert geo_item.id == item.id
      assert geo_item.source_id == source.id
      assert geo_item.external_id == "12354"
      assert geo_item.title == "Example Item"

      {:ok, updated_item} =
        GeoData.upsert_geo_item(%{
          source_id: source.id,
          external_id: "12354",
          title: "New Example",
          subtitle: "Amazing Title"
        })

      assert updated_item.id == item.id
      assert updated_item.source_id == source.id
      assert updated_item.external_id == "12354"
      assert updated_item.title == "New Example"
      assert updated_item.subtitle == "Amazing Title"
    end
  end

  describe "get_point/1" do
    test "it returns a point based on a geo point" do
      item =
        insert(:geo_item,
          geo_point: %Geo.Point{
            coordinates: {13.2677, 52.49},
            properties: %{},
            srid: 4326
          }
        )

      assert GeoData.get_point(item) == %{lat: 52.49, lng: 13.2677}
    end

    test "it returns a point based on a a geo polygon" do
      item =
        insert(:geo_item,
          geo_geometry: %Geo.MultiPolygon{
            coordinates: [
              [
                [
                  {13.4343272619011, 52.5405861405958},
                  {13.4371221660038, 52.5396388337848},
                  {13.4376794632698, 52.5401260460066},
                  {13.4392118915391, 52.5394073982677},
                  {13.4392324135568, 52.5395221795781},
                  {13.4343272619011, 52.5405861405958}
                ]
              ]
            ],
            properties: %{},
            srid: 4326
          }
        )

      assert GeoData.get_point(item) == %{lat: 52.53999676943175, lng: 13.436779837728949}
    end

    test "it returns nil if no geometry is inside the geo item" do
      item = insert(:geo_item)

      assert GeoData.get_point(item) == %{lat: nil, lng: nil}
    end
  end

  describe "get_items_near/3" do
    setup do
      insert(:geo_item,
        title: "One",
        geo_point: %Geo.Point{
          coordinates: {13.2677, 52.49},
          properties: %{},
          srid: 4326
        }
      )

      insert(:geo_item,
        title: "Two",
        date_end: Timex.shift(Timex.now(), months: -10),
        geo_point: %Geo.Point{
          coordinates: {13.2679, 52.51},
          properties: %{},
          srid: 4326
        }
      )

      insert(:geo_item,
        title: "Three",
        geo_geometry: %Geo.MultiPolygon{
          coordinates: [
            [
              [
                {13.4343272619011, 52.5405861405958},
                {13.4371221660038, 52.5396388337848},
                {13.4376794632698, 52.5401260460066},
                {13.4392118915391, 52.5394073982677},
                {13.4392324135568, 52.5395221795781},
                {13.4343272619011, 52.5405861405958}
              ]
            ]
          ],
          properties: %{},
          srid: 4326
        }
      )

      insert(:geo_item,
        title: "Four",
        participation_open: true,
        geo_point: %Geo.Point{
          coordinates: {13.2679, 52.51},
          properties: %{},
          srid: 4326
        }
      )

      insert(:geo_item,
        title: "Five",
        date_end: Timex.parse!("2001-01-01", "{YYYY}-{0M}-{0D}"),
        geo_point: %Geo.Point{
          coordinates: {13.2689, 52.61},
          properties: %{},
          srid: 4326
        }
      )

      %{}
    end

    test "it returns a correctly sorted list without too old items" do
      items = GeoData.get_items_near(52.51, 13.2679)
      assert 4 == length(items)
      assert ["Four", "Two", "One", "Three"] == Enum.map(items, & &1.title)
    end

    test "it returns 3 items if count is 3" do
      items = GeoData.get_items_near(52.51, 13.2679, 3)
      assert 3 == length(items)
    end
  end
end
