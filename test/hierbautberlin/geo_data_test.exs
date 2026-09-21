defmodule Hierbautberlin.GeoDataTest do
  use Hierbautberlin.DataCase

  alias Ecto.Adapters.SQL
  alias Hierbautberlin.GeoData
  alias Hierbautberlin.GeoData.AnalyzeText

  describe "get_source_by_short_name/1" do
    test "gets a source by it's short name" do
      data = insert(:source)

      geo_data = GeoData.get_source_by_short_name(data.short_name)
      assert geo_data.short_name =~ ~r/^TEST-/
      assert geo_data.name == "City Source"
      assert geo_data.url == "https://city.example.com"
      assert geo_data.copyright == "Example"
    end

    test "returns nil if source not found" do
      assert nil == GeoData.get_source_by_short_name("wow")
    end
  end

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
          copyright: "Example",
          color: "#aabbcc"
        })

      assert insert.short_name == "TEST"
      assert insert.name == "City Source"
      assert insert.url == "https://city.example.com"
      assert insert.copyright == "Example"
      assert insert.color == "#aabbcc"

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
      assert geo_data.color == "#aabbcc"
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

  describe "get_geo_item_by_short_name/2" do
    test "it returns a news item" do
      geo_item = insert(:geo_item)

      assert GeoData.get_geo_item_with_external_id(geo_item.source_id, geo_item.external_id).id ==
               geo_item.id
    end

    test "it returns nil if not found" do
      assert GeoData.get_geo_item_with_external_id(1, "not found") == nil
    end
  end

  describe "get_news_item!/1" do
    test "it returns a news item" do
      news = insert(:news_item)
      assert GeoData.get_news_item!(news.id).id == news.id
    end
  end

  describe "get_news_item_by_short_name/2" do
    test "it returns a news item" do
      news = insert(:news_item)

      assert GeoData.get_news_item_with_external_id(news.source_id, news.external_id).id ==
               news.id
    end

    test "it returns nil if not found" do
      assert GeoData.get_news_item_with_external_id(1, "not found") == nil
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
      assert GeoData.get_point(item) == %{lat: 51.504999999999995, lng: 13.004999999999999}
    end
  end

  describe "hide_geo_items_outside/2" do
    test "hides the items of the source outside of the bounding box" do
      source = insert(:source)
      point = fn lng, lat -> %Geo.Point{coordinates: {lng, lat}, srid: 4326} end

      berlin = insert(:geo_item, source: source, geo_point: point.(13.4, 52.5), geometry: nil)
      leipzig = insert(:geo_item, source: source, geo_point: point.(12.37, 51.34), geometry: nil)
      other_source = insert(:geo_item, geo_point: point.(12.37, 51.34), geometry: nil)

      assert GeoData.hide_geo_items_outside(source, {13.08, 52.33, 13.77, 52.68}) == 1

      refute Repo.reload!(berlin).hidden
      assert Repo.reload!(leipzig).hidden
      refute Repo.reload!(other_source).hidden
    end
  end

  describe "hide_missing_geo_items/2" do
    test "hides items that are not in the import anymore" do
      source = insert(:source)

      [one, two, three] =
        for i <- 1..3, do: insert(:geo_item, source: source, external_id: "#{i}")

      other_source_item = insert(:geo_item)

      assert GeoData.hide_missing_geo_items(source, ["1", "2"]) == 1

      refute Repo.reload!(one).hidden
      refute Repo.reload!(two).hidden
      assert Repo.reload!(three).hidden
      refute Repo.reload!(other_source_item).hidden
    end

    test "does not hide anything when the import looks incomplete" do
      source = insert(:source)
      for i <- 1..3, do: insert(:geo_item, source: source, external_id: "#{i}")

      assert GeoData.hide_missing_geo_items(source, []) == 0
      assert GeoData.hide_missing_geo_items(source, ["1"]) == 0
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
      first_street = List.first(result.streets)
      assert street.geometry == first_street.geometry
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
      street_one = insert(:street, name: "Annestine-Beyer-Straße")
      street_two = insert(:street, name: "Bornstraße")
      AnalyzeText.add_streets([street_one, street_two])

      result =
        GeoData.analyze_text(
          "Wir haben eine neue Baustelle in der Annestine-Beyer-Strasse und Bornstrasse die..."
        )

      assert [street_one.id, street_two.id] == Enum.map(result.streets, & &1.id)
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

    test "it keeps the street as context if the house number can't be found or interpolated" do
      street = insert(:street, name: "Anne Knight Straße")
      insert(:street_number, number: "20A", geo_street_id: street.id)
      AnalyzeText.add_streets([street])

      result = GeoData.analyze_text("In der Anne Knight Straße 25 wird ...")

      assert Enum.empty?(result.street_numbers)
      assert Enum.empty?(result.interpolated)
      # one known number gives no gradient to interpolate along
      assert Enum.empty?(result.streets)
      assert [street.id] == result.context_streets |> Enum.map(& &1.id)
    end

    test "it finds a house number written with a leading zero" do
      street = insert(:street, name: "Clara Zetkin Straße", street_numbers: [])
      five = insert(:street_number, number: "5", geo_street_id: street.id)
      insert(:street_number, number: "4", geo_street_id: street.id)
      insert(:street_number, number: "6", geo_street_id: street.id)
      AnalyzeText.add_streets([street])

      result = GeoData.analyze_text("In der Clara Zetkin Straße 05 wird ...")

      assert [five.id] == result.street_numbers |> Enum.map(& &1.id)
      # and it is not interpolated next to the house that already exists
      assert Enum.empty?(result.interpolated)
    end

    test "a context street keeps its point on the map, but not its geometry" do
      street =
        insert(:street,
          name: "Tony Sender Straße",
          street_numbers: [],
          geo_point: %Geo.Point{coordinates: {13.5, 52.5}, srid: 4326}
        )

      insert(:street_number, number: "20A", geo_street_id: street.id)
      AnalyzeText.add_streets([street])

      source = insert(:source)

      item =
        GeoData.upsert_news_item!(
          %{external_id: "context-1", title: "Umbau", source_id: source.id},
          "In der Tony Sender Straße 25 wird umgebaut.",
          []
        )

      assert item.context_street_ids == [street.id]
      # still linked and still visible
      assert [street.id] == Repo.preload(item, :geo_streets).geo_streets |> Enum.map(& &1.id)
      assert %Geo.MultiPoint{coordinates: [{13.5, 52.5}]} = item.geo_points
      # but the whole street is not drawn
      assert is_nil(item.geometries)
    end

    test "it interpolates a house number between its two known neighbours" do
      street = insert(:street, name: "Hedwig Dohm Straße", geometry: nil, street_numbers: [])

      insert(:street_number,
        number: "10",
        geo_street_id: street.id,
        zip: "10247",
        geo_point: %Geo.Point{coordinates: {13.0, 52.0}, srid: 4326}
      )

      insert(:street_number,
        number: "20",
        geo_street_id: street.id,
        zip: "10247",
        geo_point: %Geo.Point{coordinates: {13.1, 52.0}, srid: 4326}
      )

      AnalyzeText.add_streets([street])

      result = GeoData.analyze_text("In der Hedwig Dohm Straße 14 wird ...")

      assert Enum.empty?(result.street_numbers)
      assert Enum.empty?(result.context_streets)
      assert [interpolated] = result.interpolated
      assert interpolated.number == "14"
      assert interpolated.geo_street_id == street.id
      assert interpolated.zip == "10247"

      {lng, lat} = interpolated.geo_point.coordinates
      assert_in_delta lng, 13.04, 0.0001
      assert_in_delta lat, 52.0, 0.0001
    end

    test "it interpolates along the street, not straight through the block" do
      # an L: south to north, then west to east
      street =
        insert(:street,
          name: "Hertha Nathorff Straße",
          street_numbers: [],
          geometry: %Geo.LineString{
            coordinates: [{13.0, 52.0}, {13.0, 52.01}, {13.01, 52.01}],
            srid: 4326
          }
        )

      insert(:street_number,
        number: "10",
        geo_street_id: street.id,
        geo_point: %Geo.Point{coordinates: {13.0, 52.0}, srid: 4326}
      )

      insert(:street_number,
        number: "20",
        geo_street_id: street.id,
        geo_point: %Geo.Point{coordinates: {13.01, 52.01}, srid: 4326}
      )

      AnalyzeText.add_streets([street])

      result = GeoData.analyze_text("In der Hertha Nathorff Straße 15 wird ...")

      assert [interpolated] = result.interpolated
      {lng, lat} = interpolated.geo_point.coordinates

      # halfway *along* the line is the corner, not the diagonal midpoint
      assert_in_delta lng, 13.0, 0.0001
      assert_in_delta lat, 52.01, 0.0001
    end

    test "it interpolates on the same side of the street" do
      street = insert(:street, name: "Hermine Heusler Straße", street_numbers: [], geometry: nil)

      # odd numbers south, even numbers north
      for {number, lat} <- [{"11", 52.0}, {"21", 52.0}, {"12", 52.01}, {"20", 52.01}] do
        lng = if number in ["11", "12"], do: 13.0, else: 13.1

        insert(:street_number,
          number: number,
          geo_street_id: street.id,
          geo_point: %Geo.Point{coordinates: {lng, lat}, srid: 4326}
        )
      end

      AnalyzeText.add_streets([street])

      result = GeoData.analyze_text("In der Hermine Heusler Straße 15 wird ...")

      assert [interpolated] = result.interpolated
      {lng, lat} = interpolated.geo_point.coordinates

      # 15 is odd, so it sits between 11 and 21, not between 12 and 20
      assert_in_delta lat, 52.0, 0.0001
      assert_in_delta lng, 13.04, 0.0001
    end

    test "a street mentioned on its own keeps its geometry even with an unresolvable number" do
      street = insert(:street, name: "Lily Braun Straße", street_numbers: [])
      insert(:street_number, number: "1", geo_street_id: street.id)
      AnalyzeText.add_streets([street])

      text = "In der Lily Braun Straße wird gebaut. Die Baustelle Lily Braun Straße 99 ist groß."
      result = GeoData.analyze_text(text)

      # the plain mention wins, the street must not be linked twice
      assert [street.id] == result.streets |> Enum.map(& &1.id)
      assert Enum.empty?(result.context_streets)

      source = insert(:source)

      item =
        GeoData.upsert_news_item!(
          %{external_id: "both-1", title: "Umbau", source_id: source.id},
          text,
          []
        )

      assert [street.id] == Repo.preload(item, :geo_streets).geo_streets |> Enum.map(& &1.id)
      assert item.context_street_ids == []
      refute is_nil(item.geometries)
    end

    test "it does not extrapolate beyond the known house numbers" do
      street =
        insert(:street, name: "Lida Gustava Heymann Straße", geometry: nil, street_numbers: [])

      insert(:street_number,
        number: "10",
        geo_street_id: street.id,
        geo_point: %Geo.Point{coordinates: {13.0, 52.0}, srid: 4326}
      )

      insert(:street_number,
        number: "20",
        geo_street_id: street.id,
        geo_point: %Geo.Point{coordinates: {13.1, 52.0}, srid: 4326}
      )

      AnalyzeText.add_streets([street])

      result = GeoData.analyze_text("In der Lida Gustava Heymann Straße 90 wird ...")

      assert Enum.empty?(result.interpolated)
      assert [street.id] == result.context_streets |> Enum.map(& &1.id)
    end

    test "it stores an interpolated house number and uses it as the point of the news item" do
      street = insert(:street, name: "Emma Ihrer Straße", geometry: nil, street_numbers: [])

      insert(:street_number,
        number: "10",
        geo_street_id: street.id,
        geo_point: %Geo.Point{coordinates: {13.0, 52.0}, srid: 4326}
      )

      insert(:street_number,
        number: "20",
        geo_street_id: street.id,
        geo_point: %Geo.Point{coordinates: {13.1, 52.0}, srid: 4326}
      )

      AnalyzeText.add_streets([street])

      source = insert(:source)

      item =
        GeoData.upsert_news_item!(
          %{external_id: "interpolated-1", title: "Umbau", source_id: source.id},
          "In der Emma Ihrer Straße 14 wird umgebaut.",
          []
        )

      assert [number] = Repo.preload(item, :geo_street_numbers).geo_street_numbers
      assert number.number == "14"
      assert number.interpolated

      # the item gets the interpolated point, not the whole street
      assert %Geo.MultiPoint{coordinates: [{lng, _lat}]} = item.geo_points
      assert_in_delta lng, 13.04, 0.0001
      assert is_nil(item.geometries)
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
          %{districts: ["Mitte"]}
        )

      assert Enum.empty?(result.places)

      result =
        GeoData.analyze_text(
          "Hier in Buch",
          %{districts: ["Mitte"]}
        )

      assert [place_buch.id] == result.places |> Enum.map(& &1.id)

      result =
        GeoData.analyze_text(
          "Hier in Buch.",
          %{districts: ["Mitte"]}
        )

      assert [place_buch.id] == result.places |> Enum.map(& &1.id)
    end

    test "it should find the best match, not all of them" do
      street_one = insert(:street, name: "Rachel Cargle Straße", district: "Mitte")
      street_number = insert(:street_number, number: "10", geo_street_id: street_one.id)
      street_two = insert(:street, name: "Straße 10", district: "Mitte")
      AnalyzeText.add_streets([street_one, street_two])

      result =
        GeoData.analyze_text(
          "In der Rachel Cargle Straße 10 wird ein neuer ...",
          %{districts: ["Mitte"]}
        )

      assert [] == result.streets
      assert [street_number.id] == result.street_numbers |> Enum.map(& &1.id)

      result =
        GeoData.analyze_text(
          "In Straße 10 wird ein neuer ...",
          %{districts: ["Mitte"]}
        )

      assert [street_two.id] == result.streets |> Enum.map(& &1.id)
      assert [] == result.street_numbers |> Enum.map(& &1.id)
    end

    test "Match should not be part of another word" do
      street = insert(:street, name: "Straße 5", district: "Friedrichshain-Kreuzberg")

      AnalyzeText.add_streets([street])

      result =
        GeoData.analyze_text(
          "Auf der James Baldwin Strasse 51 ...",
          %{districts: ["Friedrichshain-Kreuzberg"]}
        )

      assert Enum.empty?(result.streets)

      result =
        GeoData.analyze_text(
          "Auf der James-Baldwin-Strasse 5 ...",
          %{districts: ["Friedrichshain-Kreuzberg"]}
        )

      assert Enum.empty?(result.streets)

      result =
        GeoData.analyze_text(
          "Auf der Baldwinstrasse 5 ...",
          %{districts: ["Friedrichshain-Kreuzberg"]}
        )

      assert Enum.empty?(result.streets)
    end

    test "Should ignore newlines" do
      street =
        insert(:street,
          name: "Ruth Bader Ginsburg Straße 5",
          district: "Friedrichshain-Kreuzberg"
        )

      AnalyzeText.add_streets([street])

      result =
        GeoData.analyze_text(
          "Auf der Ruth Bader\nGinsburg Straße 5",
          %{districts: ["Friedrichshain-Kreuzberg"]}
        )

      assert [street.id] == result.streets |> Enum.map(& &1.id)
    end
  end

  describe "upsert_news_item!/3" do
    test "creates a news item and analyzes the full text" do
      source = insert(:source)

      street = insert(:street, name: "Karl-Marx-Straße", district: "Mitte")
      AnalyzeText.add_streets([street])

      place_park = insert(:place, name: "Rosa Parks Park", district: "Mitte")
      AnalyzeText.add_places([place_park])

      time_now = DateTime.truncate(DateTime.now!("Etc/UTC"), :second)

      news_item =
        GeoData.upsert_news_item!(
          %{
            external_id: "http://example.com",
            title: "My New Title",
            url: "http://example.com",
            content: "My Content",
            published_at: time_now,
            source_id: source.id
          },
          "This is the full text of the Rosa Parks Park announcement in the Karl-Marx-Straße 20",
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
      assert [street.id] == news_item.geo_streets |> Enum.map(& &1.id)

      updated_news_item =
        GeoData.upsert_news_item!(
          %{
            external_id: "http://example.com",
            title: "My Updated Title",
            source_id: source.id
          },
          "This is the full text of the Rosa Parks Park announcement in the Karl-Marx-Straße 20",
          districts: []
        )

      assert updated_news_item.id == news_item.id
      assert updated_news_item.title == "My Updated Title"
    end
  end

  describe "search_street/1" do
    setup do
      insert(:street, name: "Rosa-Luxemburg-Straße", street_number_count: 10)
      insert(:street, name: "Rosa Straße", street_number_count: 4)
      insert(:street, name: "Luxemburg Straße", street_number_count: 1)

      :ok
    end

    test "finds streets starting with Ro" do
      result = GeoData.search_street("Ro")
      assert Enum.map(result, & &1.name) == ["Rosa-Luxemburg-Straße", "Rosa Straße"]
    end

    test "finds words in the name before other matches" do
      result = GeoData.search_street("luxemburg")
      assert Enum.map(result, & &1.name) == ["Luxemburg Straße", "Rosa-Luxemburg-Straße"]

      result = GeoData.search_street("uxemburg")
      assert Enum.map(result, & &1.name) == ["Rosa-Luxemburg-Straße", "Luxemburg Straße"]
    end

    test "finds streets with ss instead of ß and abbreviations" do
      assert [%{name: "Rosa Straße"} | _] = GeoData.search_street("rosa strasse")

      assert Enum.map(GeoData.search_street("Luxemburg Str."), & &1.name) == [
               "Luxemburg Straße",
               "Rosa-Luxemburg-Straße"
             ]

      assert Enum.map(GeoData.search_street("rosa luxemburg"), & &1.name) == [
               "Rosa-Luxemburg-Straße"
             ]
    end

    test "prefers names starting with the search over more important streets" do
      insert(:street, name: "Unter den Linden", street_number_count: 70)
      insert(:street, name: "Linienstraße", street_number_count: 192)
      insert(:street, name: "Lindenstraße", street_number_count: 188)

      assert [%{name: "Unter den Linden"}] = GeoData.search_street("unter den lin")

      # a word starting with "linden" comes before the typo match "Linienstraße"
      assert ["Lindenstraße", "Unter den Linden", "Linienstraße"] ==
               Enum.map(GeoData.search_street("linden"), & &1.name)
    end

    test "tolerates typos at the start of the name" do
      insert(:street, name: "Sonnenallee", street_number_count: 275)
      assert [%{name: "Sonnenallee"}] = GeoData.search_street("Sonenallee")
    end

    test "keeps the normalized name up to date" do
      street = insert(:street, name: "Alt-Moabit")
      assert [%{name: "Alt-Moabit"}] = GeoData.search_street("alt moabit")

      street |> Ecto.Changeset.change(name: "Neu-Moabit") |> Repo.update!()
      assert [] = GeoData.search_street("alt moabit")
      assert [%{name: "Neu-Moabit"}] = GeoData.search_street("neu moabit")
    end
  end

  describe "get_geo_items_for_locations_since/2" do
    test "it returns a list of geo items" do
      insert(:geo_item,
        title: "Distant Point Item",
        geo_point: %Geo.Point{
          coordinates: {13, 52},
          properties: %{},
          srid: 4326
        }
      )

      old_item =
        insert(:geo_item,
          title: "Old Point Item",
          geo_point: %Geo.Point{
            coordinates: {13.3789047176, 52.51650032279},
            properties: %{},
            srid: 4326
          }
        )

      SQL.query!(
        Hierbautberlin.Repo,
        "UPDATE geo_items SET inserted_at = '2010-01-01 4:30' WHERE id= $1",
        [old_item.id]
      )

      insert(:geo_item,
        title: "Point Item",
        geo_point: %Geo.Point{
          coordinates: {13.26805, 52.525},
          properties: %{},
          srid: 4326
        }
      )

      insert(:geo_item,
        title: "Polygon Item",
        geometry: %Geo.MultiPolygon{
          coordinates: [
            [
              [
                {13.26805, 52.525},
                {13.26805, 52.530},
                {13.26810, 52.530},
                {13.26805, 52.525}
              ]
            ]
          ]
        }
      )

      result =
        GeoData.get_geo_items_for_locations_since(
          [
            %{
              location: {52.51, 13.2679},
              radius: 2000
            }
          ],
          Timex.parse!("2013-03-05", "{YYYY}-{0M}-{0D}")
        )

      assert ["Point Item", "Polygon Item"] == Enum.map(result, & &1.title)
    end
  end

  describe "get_news_items_for_locations_since/2" do
    test "it returns a list of news items" do
      insert(:news_item)
      old_news = insert(:news_item, title: "Old News")

      SQL.query!(
        Hierbautberlin.Repo,
        "UPDATE news_items SET inserted_at = '2010-01-01 4:30' WHERE id= $1",
        [old_news.id]
      )

      result =
        GeoData.get_news_items_for_locations_since(
          [
            %{
              location: {52.51, 13.2679},
              radius: 2000
            }
          ],
          Timex.parse!("2013-03-05", "{YYYY}-{0M}-{0D}")
        )

      assert ["This is a nice title"] == Enum.map(result, & &1.title)
    end
  end
end
