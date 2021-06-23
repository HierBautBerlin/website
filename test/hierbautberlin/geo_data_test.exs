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

  describe "analyze_text/1" do
    setup do
      street = insert(:street, name: "Isabel-de-Villena-Straße")
      Hierbautberlin.GeoData.AnalyzeText.add_streets([street])
      %{}
    end

    test "it should return a street if the text contains it" do
      street = insert(:street, name: "Emma Watson Straße")
      Hierbautberlin.GeoData.AnalyzeText.add_streets([street])

      result =
        GeoData.analyze_text("Wir haben eine neue Baustelle in der Emma Watson Straße die...")

      assert [street.id] == Enum.map(result.streets, & &1.id)
    end

    test "it should return two streets" do
      street_1 = insert(:street, name: "Laura-Cereta-Straße")
      street_2 = insert(:street, name: "Balaram-Das-Straße")
      Hierbautberlin.GeoData.AnalyzeText.add_streets([street_1, street_2])

      result =
        GeoData.analyze_text(
          "Der neue Spieplatz an der Ecke Laura-Cereta-Straße und Balaram-Das-Straße"
        )

      assert [street_1.id, street_2.id] == result.streets |> Enum.map(& &1.id) |> Enum.sort()
    end

    test "it should transform Strasse to Straße and find words with it" do
      street = insert(:street, name: "Annestine-Beyer-Straße")
      Hierbautberlin.GeoData.AnalyzeText.add_streets([street])

      result =
        GeoData.analyze_text(
          "Wir haben eine neue Baustelle in der Annestine-Beyer-Strasse die..."
        )

      assert [street.id] == Enum.map(result.streets, & &1.id)
    end

    test "it should transform Str. to Straße" do
      street = insert(:street, name: "Mary-Shelley-Straße")
      Hierbautberlin.GeoData.AnalyzeText.add_streets([street])

      result =
        GeoData.analyze_text("Wir haben eine neue Baustelle in der Mary-Shelley-Str. die...")

      assert [street.id] == Enum.map(result.streets, & &1.id)
    end

    test "it should try to figure out which street is ment when it is not unique based on other info" do
      street_1 = insert(:street, name: "Jane-Addams-Straße")
      street_2 = insert(:street, name: "Jane-Addams-Straße", district: "Neuköln")
      Hierbautberlin.GeoData.AnalyzeText.add_streets([street_1, street_2])

      result =
        GeoData.analyze_text(
          "Wir haben eine neue Baustelle in der Jane-Addams-Straße die...",
          %{districts: ["Friedrichshain", "Mitte"]}
        )

      assert [street_1.id] == result.streets |> Enum.map(& &1.id)
    end

    test "it should try to figure out which street is ment when it is not unique and other streets are present, too" do
      street_1 = insert(:street, name: "Anna-Wheeler-Straße")
      street_2 = insert(:street, name: "Frances-Wright-Straße")
      street_3 = insert(:street, name: "Anna-Wheeler-Straße", district: "Neuköln")
      Hierbautberlin.GeoData.AnalyzeText.add_streets([street_1, street_2, street_3])

      result =
        GeoData.analyze_text(
          "Wir haben eine neue Baustelle in der Anna-Wheeler-Straße Ecke Frances-Wright-Straße die..."
        )

      assert [street_1.id, street_2.id] == result.streets |> Enum.map(& &1.id) |> Enum.sort()
    end

    test "it should try to figure out which street is ment when it is not unique and other street numbers are present, too" do
      street_1 = insert(:street, name: "Robin-Morgan-Straße")
      street_2 = insert(:street, name: "Laura-Mulvey-Straße")
      street_number = insert(:street_number, number: "20", geo_street_id: street_2.id)
      street_3 = insert(:street, name: "Robin-Morgan-Straße", district: "Neuköln")
      Hierbautberlin.GeoData.AnalyzeText.add_streets([street_1, street_2, street_3])

      result =
        GeoData.analyze_text(
          "Wir haben eine neue Baustelle in der Robin-Morgan-Straße Ecke Laura-Mulvey-Straße 20 die..."
        )

      assert [street_1.id] == result.streets |> Enum.map(& &1.id) |> Enum.sort()
      assert [street_number.id] == result.street_numbers |> Enum.map(& &1.id) |> Enum.sort()
    end

    test "it should find the exact house number if the text contains it" do
      street = insert(:street, name: "Molly Yard Straße")
      street_number = insert(:street_number, number: "20", geo_street_id: street.id)
      Hierbautberlin.GeoData.AnalyzeText.add_streets([street])

      result = GeoData.analyze_text("In der Molly Yard Straße 20 wird ...")
      assert [street_number.id] == result.street_numbers |> Enum.map(& &1.id)
    end

    test "it should use the street if the house number cannot be found" do
      street = insert(:street, name: "Anne Knight Straße")
      insert(:street_number, number: "20A", geo_street_id: street.id)
      Hierbautberlin.GeoData.AnalyzeText.add_streets([street])

      result = GeoData.analyze_text("In der Anne Knight Straße 25 wird ...")
      assert Enum.empty?(result.street_numbers)
      assert [street.id] == result.streets |> Enum.map(& &1.id)
    end

    test "it should find the exact house number if the street exists in two districts" do
      street = insert(:street, name: "Fatima Mernissi Weg", district: "Mitte")
      street_number = insert(:street_number, number: "78", geo_street_id: street.id)

      street_neukoeln = insert(:street, name: "Fatima Mernissi Weg", district: "Neuköln")
      insert(:street_number, number: "78", geo_street_id: street_neukoeln.id)

      Hierbautberlin.GeoData.AnalyzeText.add_streets([street, street_neukoeln])

      result =
        GeoData.analyze_text(
          "In dem Fatima Mernissi Weg 78 wird ...",
          %{districts: ["Friedrichshain", "Mitte"]}
        )

      assert [street_number.id] == result.street_numbers |> Enum.map(& &1.id)
    end

    test "it should find the exact house number if the text contains a house number with letter like 2A or 2 A" do
      street = insert(:street, name: "John Neal Straße")
      street_number = insert(:street_number, number: "120C", geo_street_id: street.id)
      Hierbautberlin.GeoData.AnalyzeText.add_streets([street])

      result = GeoData.analyze_text("In der John Neal Straße 120 c wird ...")
      assert [street_number.id] == result.street_numbers |> Enum.map(& &1.id)
    end

    test "it should find the exact house number if the text contains a dashed version like 73/74 or 70-80" do
      street = insert(:street, name: "Sojourner Truth Straße")
      street_number = insert(:street_number, number: "73", geo_street_id: street.id)
      Hierbautberlin.GeoData.AnalyzeText.add_streets([street])

      result = GeoData.analyze_text("In der Sojourner Truth Strasse 73/70 wird ...")
      assert [street_number.id] == result.street_numbers |> Enum.map(& &1.id)

      result = GeoData.analyze_text("In der Sojourner Truth Strasse 73-70 wird ...")
      assert [street_number.id] == result.street_numbers |> Enum.map(& &1.id)
    end
  end
end
