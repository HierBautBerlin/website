defmodule Hierbautberlin.GeoDataTest do
  use Hierbautberlin.DataCase

  alias Hierbautberlin.GeoData
  alias Hierbautberlin.GeoData.{GeoMapItem, GeoPosition, AnalyzeText}

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

  describe "get_news_item!/1" do
    test "it returns a news item" do
      news = insert(:news_item)
      assert GeoData.get_news_item!(news.id).id == news.id
    end
  end

  describe "get_geo_street!/1" do
    test "it returns a geo street" do
      geo_street = insert(:street)
      assert GeoData.get_geo_street!(geo_street.id).id == geo_street.id
    end
  end

  describe "get_geo_street_number!/1" do
    test "it returns a geo street number" do
      geo_street_number = insert(:street_number_with_street)
      assert GeoData.get_geo_street_number!(geo_street_number.id).id == geo_street_number.id
    end
  end

  describe "get_geo_place!/1" do
    test "it returns a geo place" do
      geo_place = insert(:place)
      assert GeoData.get_geo_place!(geo_place.id).id == geo_place.id
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
          geometry: %Geo.MultiPolygon{
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

    test "it returns a coordinate for a news item with geo_points" do
      item = insert(:news_item)
      assert GeoData.get_point(item) == %{lat: 52.0, lng: 13.0}
    end

    test "it returns a coordinate for a news item with geometries" do
      item = Map.merge(insert(:news_item), %{geo_points: nil})
      assert GeoData.get_point(item) == %{lat: 52.05, lng: 13.05}
    end
  end

  describe "get_items_near/3" do
    setup do
      insert(:geo_item,
        title: "One",
        geo_point: %Geo.Point{
          coordinates: {13.26789, 52.509},
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
        geometry: %Geo.MultiPolygon{
          coordinates: [
            [
              [
                {13.2679, 52.51},
                {13.2679, 52.55},
                {13.2680, 52.55},
                {13.2679, 52.51}
              ]
            ]
          ],
          properties: %{},
          srid: 4326
        }
      )

      four =
        insert(:geo_item,
          title: "Four",
          subtitle: "Four Subtitle",
          description: "Four Description",
          participation_open: true,
          date_end: Timex.parse!("2021-01-01", "{YYYY}-{0M}-{0D}"),
          geo_point: %Geo.Point{
            coordinates: {13.2679, 52.51},
            properties: %{},
            srid: 4326
          },
          url: "https://example.com"
        )

      insert(:geo_item,
        title: "Five, too old",
        date_end: Timex.parse!("2001-01-01", "{YYYY}-{0M}-{0D}"),
        geo_point: %Geo.Point{
          coordinates: {13.2678, 52.515},
          properties: %{},
          srid: 4326
        }
      )

      insert(:geo_item,
        title: "Six, hidden",
        geo_point: %Geo.Point{
          coordinates: {13.26789, 52.509},
          properties: %{},
          srid: 4326
        },
        hidden: true
      )

      news_item = insert(:news_item)
      insert(:news_item, title: "Hidden News Item", hidden: true)

      %{four: four, news_item: news_item}
    end

    test "it returns a correctly sorted list without too old items", %{
      four: four,
      news_item: news_item
    } do
      items = GeoData.get_items_near(52.51, 13.2679)
      assert 5 == length(items)

      assert ["Four", "This is a nice title", "Two", "One", "Three"] ==
               Enum.map(items, & &1.title)

      first = List.first(items)

      four_id = four.id
      source_id = four.source_id
      geo_point = four.geo_point
      geo_metry = four.geometry

      assert %GeoMapItem{
               title: "Four",
               subtitle: "Four Subtitle",
               description: "Four Description",
               id: ^four_id,
               type: :geo_item,
               newest_date: ~U[2021-01-01 00:00:00Z],
               url: "https://example.com",
               participation_open: true,
               source: %{
                 id: ^source_id
               },
               item: %{
                 id: ^four_id
               },
               positions: [
                 %GeoPosition{
                   type: :geo_item,
                   id: ^four_id,
                   geopoint: ^geo_point,
                   geometry: ^geo_metry
                 }
               ]
             } = first

      second_item = Enum.at(items, 1)

      news_id = news_item.id
      news_source_id = news_item.source_id
      news_published_at = news_item.published_at

      assert %GeoMapItem{
               title: "This is a nice title",
               subtitle: nil,
               description: "This is a nice content",
               id: ^news_id,
               type: :news_item,
               newest_date: ^news_published_at,
               url: "https://www.example.com",
               participation_open: false,
               source: %{
                 id: ^news_source_id
               },
               item: %{
                 id: ^news_id
               },
               positions: [
                 %Hierbautberlin.GeoData.GeoPosition{
                   geometry: nil,
                   geopoint: %Geo.Point{
                     coordinates: {13.0, 52.0},
                     properties: %{},
                     srid: 4326
                   },
                   type: :geo_street
                 },
                 %Hierbautberlin.GeoData.GeoPosition{
                   geometry: nil,
                   geopoint: %Geo.Point{coordinates: {13.0, 52.0}, properties: %{}, srid: 4326},
                   type: :geo_street_number
                 },
                 %Hierbautberlin.GeoData.GeoPosition{
                   geometry: %Geo.Polygon{
                     coordinates: [[{13.0, 52.0}, {13.1, 52.1}, {13.1, 52.0}, {13.0, 52.0}]],
                     properties: %{},
                     srid: 4326
                   },
                   geopoint: %Geo.Point{
                     coordinates: {13.2679, 52.51},
                     properties: %{},
                     srid: 4326
                   },
                   type: :geo_place
                 }
               ]
             } = second_item
    end

    test "it returns 3 items if count is 3" do
      items = GeoData.get_items_near(52.51, 13.2679, 3)
      assert 3 == length(items)
    end
  end

  describe "analyze_text/1" do
    setup do
      street = insert(:street, name: "Isabel-de-Villena-Straße")
      AnalyzeText.add_streets([street])

      on_exit(fn ->
        AnalyzeText.reset_index()
      end)

      %{}
    end

    test "it should return a street if the text contains it" do
      street = insert(:street, name: "Emma Watson Straße")
      AnalyzeText.add_streets([street])

      result =
        GeoData.analyze_text("Wir haben eine neue Baustelle in der Emma Watson Straße die...")

      assert [street.id] == Enum.map(result.streets, & &1.id)
    end

    test "it should return two streets" do
      street_1 = insert(:street, name: "Laura-Cereta-Straße")
      street_2 = insert(:street, name: "Balaram-Das-Straße")
      AnalyzeText.add_streets([street_1, street_2])

      result =
        GeoData.analyze_text(
          "Der neue Spieplatz an der Ecke Laura-Cereta-Straße und Balaram-Das-Straße"
        )

      assert [street_1.id, street_2.id] == result.streets |> Enum.map(& &1.id) |> Enum.sort()
    end

    test "it should transform Strasse to Straße and find words with it" do
      street = insert(:street, name: "Annestine-Beyer-Straße")
      AnalyzeText.add_streets([street])

      result =
        GeoData.analyze_text(
          "Wir haben eine neue Baustelle in der Annestine-Beyer-Strasse die..."
        )

      assert [street.id] == Enum.map(result.streets, & &1.id)
    end

    test "it should transform Str. to Straße" do
      street = insert(:street, name: "Mary-Shelley-Straße")
      AnalyzeText.add_streets([street])

      result =
        GeoData.analyze_text("Wir haben eine neue Baustelle in der Mary-Shelley-Str. die...")

      assert [street.id] == Enum.map(result.streets, & &1.id)
    end

    test "it should try to figure out which street is ment when it is not unique based on other info" do
      street_1 = insert(:street, name: "Jane-Addams-Straße")
      street_2 = insert(:street, name: "Jane-Addams-Straße", district: "Neuköln")
      AnalyzeText.add_streets([street_1, street_2])

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
      AnalyzeText.add_streets([street_1, street_2, street_3])

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
      AnalyzeText.add_streets([street_1, street_2, street_3])

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
      AnalyzeText.add_streets([street])

      result = GeoData.analyze_text("In der Molly Yard Straße 20 wird ...")
      assert [street_number.id] == result.street_numbers |> Enum.map(& &1.id)
    end

    test "it should use the street if the house number cannot be found" do
      street = insert(:street, name: "Anne Knight Straße")
      insert(:street_number, number: "20A", geo_street_id: street.id)
      AnalyzeText.add_streets([street])

      result = GeoData.analyze_text("In der Anne Knight Straße 25 wird ...")
      assert Enum.empty?(result.street_numbers)
      assert [street.id] == result.streets |> Enum.map(& &1.id)
    end

    test "it should find the exact house number if the street exists in two districts" do
      street = insert(:street, name: "Fatima Mernissi Weg", district: "Mitte")
      street_number = insert(:street_number, number: "78", geo_street_id: street.id)

      street_neukoeln = insert(:street, name: "Fatima Mernissi Weg", district: "Neuköln")
      insert(:street_number, number: "78", geo_street_id: street_neukoeln.id)

      AnalyzeText.add_streets([street, street_neukoeln])

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
      AnalyzeText.add_streets([street])

      result =
        GeoData.analyze_text(
          "In der John Neal Straße 120 c wird am Haus der John Neal Straße 120 c ..."
        )

      assert [street_number.id] == result.street_numbers |> Enum.map(& &1.id)
    end

    test "it should find the exact house number if the text contains a dashed version like 73/74 or 70-80" do
      street = insert(:street, name: "Sojourner Truth Straße")
      street_number = insert(:street_number, number: "73", geo_street_id: street.id)
      AnalyzeText.add_streets([street])

      result = GeoData.analyze_text("In der Sojourner Truth Strasse 73/70 wird ...")
      assert [street_number.id] == result.street_numbers |> Enum.map(& &1.id)

      result = GeoData.analyze_text("In der Sojourner Truth Strasse 73-70 wird ...")
      assert [street_number.id] == result.street_numbers |> Enum.map(& &1.id)
    end

    test "it should find a park" do
      park = insert(:place, name: "Sojourner-Truth-Park")
      AnalyzeText.add_places([park])

      result = GeoData.analyze_text("Im Sojourner-Truth-Park wird ein neuer ...")
      assert [park.id] == result.places |> Enum.map(& &1.id)
    end

    test "it should favour a park if a street is found with the same name of a park" do
      street = insert(:street, name: "Boxhagener Platz")
      AnalyzeText.add_streets([street])

      park = insert(:place, name: "Boxhagener Platz")
      AnalyzeText.add_places([park])

      result = GeoData.analyze_text("Am Boxhagener Platz wird ein neuer ...")
      assert Enum.empty?(result.streets)
      assert [park.id] == result.places |> Enum.map(& &1.id)
    end

    test "it should find two streets with bla- and otherstreet" do
      street_one = insert(:street, name: "Blastraße")
      street_two = insert(:street, name: "Otherstraße")
      AnalyzeText.add_streets([street_one, street_two])

      result = GeoData.analyze_text("An der Bla- und Otherstraße wird ...")
      assert [street_one.id, street_two.id] == result.streets |> Enum.map(& &1.id) |> Enum.sort()
    end

    test "it should find two streets with foo-, bar- and fizzrstreet" do
      street_one = insert(:street, name: "Foostraße")
      street_two = insert(:street, name: "Barstraße")
      street_three = insert(:street, name: "Fizzstraße")
      AnalyzeText.add_streets([street_one, street_two, street_three])

      result = GeoData.analyze_text("An der Foo-, Bar- und Fizzstraße wird ...")

      assert [street_one.id, street_two.id, street_three.id] ==
               result.streets |> Enum.map(& &1.id) |> Enum.sort()
    end

    test "it should favour the street number if it is found with the same name of a park" do
      street = insert(:street, name: "Wakanda Platz")
      street_number = insert(:street_number, number: "42", geo_street_id: street.id)
      AnalyzeText.add_streets([street])

      park = insert(:place, name: "Wakanda Platz")
      AnalyzeText.add_places([park])

      result = GeoData.analyze_text("Am Wakanda Platz 42 wird ein neuer ...")
      assert Enum.empty?(result.places)
      assert [street_number.id] == result.street_numbers |> Enum.map(& &1.id)
    end

    test "it uses the place in the correct district if more than one is found" do
      place_fhain = insert(:place, name: "Rathausplatz", district: "Friedrichshain")
      place_mitte = insert(:place, name: "Rathausplatz", district: "Mitte")
      AnalyzeText.add_places([place_fhain, place_mitte])

      result =
        GeoData.analyze_text(
          "Auf dem Rathausplatz wird ein neuer ...",
          %{districts: ["Kreuzberg", "Mitte"]}
        )

      assert [place_mitte.id] == result.places |> Enum.map(& &1.id)
    end

    test "if a lor and a street have the same name, return the street" do
      street = insert(:street, name: "Skalitzer Platz", district: "Neuköln")
      AnalyzeText.add_streets([street])

      place = insert(:place, name: "Skalitzer Platz", district: "Mitte", type: "LOR")
      AnalyzeText.add_places([place])

      result =
        GeoData.analyze_text(
          "Am Skalitzer Platz wird ein neuer ...",
          %{districts: ["Kreuzberg", "Mitte"]}
        )

      assert Enum.empty?(result.places)
      assert [street.id] == result.streets |> Enum.map(& &1.id)
    end

    test "if a lor and a street have the same district, return the street" do
      street = insert(:street, name: "Bergstraße", district: "Neuköln")
      AnalyzeText.add_streets([street])

      place = insert(:place, name: "Turm Platz", district: "Neuköln", type: "LOR")
      AnalyzeText.add_places([place])

      result =
        GeoData.analyze_text(
          "In der Bergstraße am Turm Platz wird ein neuer ...",
          %{districts: ["Kreuzberg", "Mitte"]}
        )

      assert Enum.empty?(result.places)
      assert [street.id] == result.streets |> Enum.map(& &1.id)
    end

    test "a place with the same name might exists twice in a district, just return one of them, prefer parks over schools over lor" do
      place_lor = insert(:place, name: "Traveplatz", district: "Mitte", type: "LOR")
      place_park = insert(:place, name: "Traveplatz", district: "Mitte", type: "Park")
      place_school = insert(:place, name: "Traveplatz", district: "Mitte", type: "School")
      AnalyzeText.add_places([place_lor, place_park, place_school])

      result =
        GeoData.analyze_text(
          "Am Traveplatz wird ein neuer ...",
          %{districts: ["Kreuzberg", "Mitte"]}
        )

      assert [place_park.id] == result.places |> Enum.map(& &1.id)
    end

    test "viertel and kiez are the same thing" do
      place_lor =
        insert(:place, name: "Severinsviertel", district: "Friedrichshain-Kreuzberg", type: "LOR")

      AnalyzeText.add_places([place_lor])

      result =
        GeoData.analyze_text(
          "Im Severinskiez wird ein neuer ...",
          %{districts: ["Friedrichshain-Kreuzberg"]}
        )

      assert [place_lor.id] == result.places |> Enum.map(& &1.id)
    end

    test "it should not find buch if only partial match" do
      place_buch = insert(:place, name: "Buch", district: "Mitte")
      AnalyzeText.add_places([place_buch])

      result =
        GeoData.analyze_text(
          "Im Buchungssystem wird ein neuer ...",
          %{districts: ["Friedrichshain-Kreuzberg"]}
        )

      assert Enum.empty?(result.places)

      result =
        GeoData.analyze_text(
          "Hier in Buch",
          %{districts: ["Friedrichshain-Kreuzberg"]}
        )

      assert [place_buch.id] == result.places |> Enum.map(& &1.id)

      result =
        GeoData.analyze_text(
          "Hier in Buch.",
          %{districts: ["Friedrichshain-Kreuzberg"]}
        )

      assert [place_buch.id] == result.places |> Enum.map(& &1.id)
    end
  end

  describe "create_news_item!/3" do
    test "creates a news item and analyzes the full text" do
      source = insert(:source)

      place_park = insert(:place, name: "Rosa Parks Park", district: "Mitte")
      AnalyzeText.add_places([place_park])

      time_now = DateTime.now!("Etc/UTC")

      news_item =
        GeoData.create_news_item!(
          %{
            external_id: "http://example.com",
            title: "My New Title",
            url: "http://example.com",
            content: "My Content",
            published_at: time_now,
            source_id: source.id
          },
          "This is the full text of the Rosa Parks Park announcement",
          districts: []
        )

      assert news_item.id != nil

      assert news_item.external_id == "http://example.com"
      assert news_item.url == "http://example.com"
      assert news_item.title == "My New Title"
      assert news_item.content == "My Content"
      assert news_item.source_id == source.id
      assert Time.diff(news_item.published_at, time_now, :second) == 0

      assert [place_park.id] == news_item.geo_places |> Enum.map(& &1.id)
    end
  end

  describe "search_street/1" do
    setup do
      insert(:street, name: "Richard-Sorge-Straße", street_number_count: 10)
      insert(:street, name: "Richard Straße", street_number_count: 4)
      insert(:street, name: "Sorge Straße", street_number_count: 1)

      :ok
    end

    test "finds streets starting with Ri" do
      result = GeoData.search_street("Ri")
      assert Enum.map(result, & &1.name) == ["Richard-Sorge-Straße", "Richard Straße"]
    end

    test "finds streets starting with orge" do
      result = GeoData.search_street("orge")
      assert Enum.map(result, & &1.name) == ["Richard-Sorge-Straße", "Sorge Straße"]
    end

    test "finds streets starting with ss instead of ß" do
      result = GeoData.search_street("strasse")

      assert Enum.map(result, & &1.name) == [
               "Richard-Sorge-Straße",
               "Richard Straße",
               "Sorge Straße"
             ]
    end
  end
end
