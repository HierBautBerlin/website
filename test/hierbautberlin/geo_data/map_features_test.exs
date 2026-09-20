defmodule Hierbautberlin.GeoData.MapFeaturesTest do
  use Hierbautberlin.DataCase

  alias Hierbautberlin.GeoData.{GeoMapItem, MapFeatures, NewsItem, Relevance}

  @center %{lat: 52.51, lng: 13.2679}

  defp point(lng, lat), do: %Geo.Point{coordinates: {lng, lat}, srid: 4326}

  defp days_ago(days) do
    DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second)
  end

  # like the importers, with the relevance calculated from the attributes
  defp insert_geo_item(attrs) do
    attrs = Map.new(attrs)
    insert(:geo_item, Map.merge(attrs, Relevance.for_geo_item(attrs)))
  end

  describe "list_items/3" do
    setup do
      insert_geo_item(title: "One", geo_point: point(13.26789, 52.509))
      insert_geo_item(title: "Two", date_end: days_ago(300), geo_point: point(13.2679, 52.51))

      insert_geo_item(
        title: "Three",
        geometry: %Geo.MultiPolygon{
          coordinates: [
            [[{13.2679, 52.51}, {13.2679, 52.55}, {13.2680, 52.55}, {13.2679, 52.51}]]
          ],
          srid: 4326
        }
      )

      four =
        insert_geo_item(
          title: "Four",
          subtitle: "Four Subtitle",
          description: "Four Description",
          participation_open: true,
          date_end: days_ago(730),
          geo_point: point(13.2679, 52.51),
          url: "https://example.com"
        )

      insert_geo_item(
        title: "Five, too old",
        date_end: days_ago(365 * 6),
        geo_point: point(13.2678, 52.515)
      )

      insert(:geo_item, title: "Six, hidden", geo_point: point(13.26789, 52.509), hidden: true)

      insert_geo_item(
        title: "Seven - Newest Item",
        participation_open: true,
        date_end: days_ago(7),
        geo_point: point(13.2679, 52.51)
      )

      insert(:geo_item, title: "Far away", geo_point: point(13.5, 52.4))

      published_at = DateTime.utc_now(:second)

      news_item =
        insert(
          :news_item,
          Map.merge(
            %{published_at: published_at},
            Relevance.for_news_item(
              "This is a nice title",
              "This is a nice content",
              published_at
            )
          )
        )

      insert(:news_item, title: "Hidden News Item", hidden: true)

      MapFeatures.refresh()

      %{four: four, news_item: news_item}
    end

    test "returns the visible items within the bounds sorted by relevance", %{
      four: four,
      news_item: news_item
    } do
      items = MapFeatures.list_items(MapFeatures.bounds_around(@center, 15), @center)

      # Importance * time * distance: the participation that ended a week ago is
      # still on top, the news item is current, items without dates count less
      # than "Two" (which ended 300 days ago, but is at the center) and the
      # participation that ended two years ago is last. "Three" is a polygon
      # that contains the center, so its distance is 0. "Far away" is outside of
      # the bounds and only fills the list up to ten items.
      assert [
               "Seven - Newest Item",
               "This is a nice title",
               "Two",
               "Three",
               "One",
               "Four",
               "Far away"
             ] == Enum.map(items, & &1.title)

      four_id = four.id
      four_source_id = four.source_id
      four_date_end = four.date_end

      assert %GeoMapItem{
               type: :geo_item,
               id: ^four_id,
               title: "Four",
               subtitle: "Four Subtitle",
               description: "Four Description",
               newest_date: ^four_date_end,
               url: "https://example.com",
               participation_open: true,
               source: %{id: ^four_source_id},
               item: %{id: ^four_id, geometry: nil, geo_point: nil}
             } = Enum.at(items, 5)

      news_id = news_item.id

      assert %GeoMapItem{
               type: :news_item,
               id: ^news_id,
               description: "This is a nice content",
               participation_open: false
             } = Enum.at(items, 1)
    end

    test "leaves out hidden sources and filters by text", %{four: four} do
      bounds = MapFeatures.bounds_around(@center, 15)

      titles = fn opts ->
        bounds |> MapFeatures.list_items(@center, opts) |> Enum.map(& &1.title)
      end

      refute "Four" in titles.(hidden_sources: [four.source_id])
      assert "One" in titles.(hidden_sources: [four.source_id])

      # title, subtitle and description, case insensitive
      assert titles.(query: "four subtitle") == ["Four"]
      assert titles.(query: "FOUR DESCRIPTION") == ["Four"]
      assert titles.(query: "  ") |> length() > 1
      # LIKE wildcards are no wildcards
      assert titles.(query: "%") == []
      assert titles.(query: "Four", hidden_sources: [four.source_id]) == []
    end

    test "leaves out old and finished items with show_old: false" do
      insert_geo_item(
        title: "Finished",
        state: "finished",
        date_end: days_ago(3),
        geo_point: point(13.2679, 52.51)
      )

      MapFeatures.refresh()

      titles = fn opts ->
        MapFeatures.bounds_around(@center, 15)
        |> MapFeatures.list_items(@center, opts)
        |> Enum.map(& &1.title)
      end

      with_old = titles.([])
      without_old = titles.(show_old: false)

      assert "Finished" in with_old
      refute "Finished" in without_old

      # "Four" ended two years ago, "Two" 300 days ago
      assert "Four" in with_old
      refute "Four" in without_old
      assert "Two" in without_old

      # items without any date stay visible
      assert "One" in without_old
    end

    test "fresh press releases are on top for six weeks" do
      presse = insert(:source, short_name: "BERLIN_PRESSE")
      other = insert(:source)

      insert_news = fn title, text, source, days ->
        published_at = days_ago(days)

        insert(
          :news_item,
          Map.merge(
            %{title: title, source: source, published_at: published_at},
            Relevance.for_news_item(title, text, published_at, source.short_name)
          )
        )
      end

      building = "Baubeginn für den Spielplatz"
      insert_news.("Press release, three weeks old", building, presse, 21)
      insert_news.("Press release, seven weeks old", building, presse, 49)
      insert_news.("Other news, three weeks old", building, other, 21)

      party =
        "Das Bezirksamt lädt zum Fest am #{Calendar.strftime(days_ago(10), "%d.%m.%Y")} ein."

      insert_news.("Press release, party is over", party, presse, 21)
      MapFeatures.refresh()

      titles =
        MapFeatures.bounds_around(@center, 15)
        |> MapFeatures.list_items(@center)
        |> Enum.map(& &1.title)

      # above "Seven - Newest Item" (current participation), the others are
      # not current anymore
      assert ["Press release, three weeks old", "Seven - Newest Item" | rest] = titles

      assert Enum.find_index(rest, &(&1 == "Other news, three weeks old")) <
               Enum.find_index(rest, &(&1 == "Press release, seven weeks old"))

      # the boost doesn't bring back events that are over
      assert Enum.find_index(rest, &(&1 == "Press release, party is over")) >
               Enum.find_index(rest, &(&1 == "This is a nice title"))
    end

    test "limits the number of items" do
      items = MapFeatures.list_items(MapFeatures.bounds_around(@center, 15), @center, limit: 3)
      assert 3 == length(items)
    end

    test "only returns items within the bounds with min_items: 0" do
      far_away = %{lat: 52.4, lng: 13.5}

      items =
        MapFeatures.list_items(MapFeatures.bounds_around(far_away, 16), far_away, min_items: 0)

      assert ["Far away"] == Enum.map(items, & &1.title)
    end

    test "fills the list up with the nearest items outside of the bounds" do
      far_away = %{lat: 52.4, lng: 13.5}

      titles =
        MapFeatures.bounds_around(far_away, 16)
        |> MapFeatures.list_items(far_away, min_items: 3)
        |> Enum.map(& &1.title)

      # the one item within the bounds first, then the nearest ones around it
      # the most relevant ones of the cluster around the center
      assert ["Far away", "Seven - Newest Item", "This is a nice title"] == titles

      # the fill up never goes beyond the limit
      assert 1 ==
               MapFeatures.bounds_around(far_away, 16)
               |> MapFeatures.list_items(far_away, min_items: 3, limit: 1)
               |> length()
    end

    test "does not fill the list up with items that are filtered out" do
      far_away = %{lat: 52.4, lng: 13.5}
      bounds = MapFeatures.bounds_around(far_away, 16)

      titles = fn opts ->
        bounds |> MapFeatures.list_items(far_away, opts) |> Enum.map(& &1.title)
      end

      assert titles.(query: "Seven") == ["Seven - Newest Item"]
      assert "Four" not in titles.(show_old: false)
    end

    test "does not show changes before the view was refreshed" do
      insert(:geo_item, title: "Not refreshed yet", geo_point: point(13.2679, 52.51))
      items = MapFeatures.list_items(MapFeatures.bounds_around(@center, 15), @center)
      refute "Not refreshed yet" in Enum.map(items, & &1.title)

      MapFeatures.refresh()
      items = MapFeatures.list_items(MapFeatures.bounds_around(@center, 15), @center)
      assert "Not refreshed yet" in Enum.map(items, & &1.title)
    end
  end

  describe "details_shape/1" do
    defp shape_parts(item) do
      item
      |> MapFeatures.details_shape()
      |> Jason.decode!()
      |> Map.fetch!("features")
      |> Enum.map(&{&1["properties"]["draw"], &1["geometry"]["type"]})
    end

    test "returns the polygons, lines and the point of a geo item" do
      item =
        insert(:geo_item,
          geo_point: point(13.2679, 52.51),
          geometry: %Geo.GeometryCollection{
            geometries: [
              %Geo.Polygon{
                coordinates: [[{13.26, 52.50}, {13.27, 52.50}, {13.27, 52.51}, {13.26, 52.50}]]
              },
              %Geo.LineString{coordinates: [{13.26, 52.52}, {13.28, 52.52}]}
            ],
            srid: 4326
          }
        )

      assert shape_parts(item) == [
               {"polygon", "Polygon"},
               {"line", "LineString"},
               {"point", "MultiPoint"}
             ]
    end

    test "returns the shape of a geo item without a point" do
      item =
        insert(:geo_item,
          geometry: %Geo.MultiLineString{
            coordinates: [[{13.26, 52.52}, {13.28, 52.52}], [{13.26, 52.53}, {13.28, 52.53}]],
            srid: 4326
          }
        )

      assert shape_parts(item) == [{"line", "MultiLineString"}]
    end

    test "returns the streets, places and points of a news item" do
      news_item = insert(:news_item)
      news_item |> NewsItem.update_cached_geometries() |> Repo.update!()

      assert shape_parts(news_item) == [
               {"polygon", "Polygon"},
               {"line", "LineString"},
               {"point", "MultiPoint"}
             ]
    end

    test "only returns the points when the shape is too big" do
      streets =
        for index <- 1..150 do
          %Geo.LineString{
            coordinates:
              for(
                step <- 0..40,
                do:
                  {13.0 + step * 0.001 + index * 0.0001,
                   52.4 + index * 0.001 + rem(step, 2) * 0.001}
              )
          }
        end

      news_item =
        insert(:news_item,
          geometries: %Geo.GeometryCollection{geometries: streets, srid: 4326},
          geo_points: %Geo.MultiPoint{coordinates: [{13.3, 52.5}], srid: 4326}
        )

      assert shape_parts(news_item) == [{"point", "MultiPoint"}]
    end

    test "is nil without a location" do
      assert MapFeatures.details_shape(insert(:geo_item)) == nil
    end
  end

  describe "tile/3" do
    test "returns an empty tile when there is nothing" do
      assert MapFeatures.tile(15, 17_600, 10_745) == <<>>
    end

    test "returns an empty tile for zoom levels below the minimum" do
      insert(:geo_item, geo_point: point(13.2679, 52.51))
      MapFeatures.refresh()

      assert MapFeatures.tile(MapFeatures.min_zoom() - 1, 0, 0) == <<>>
    end

    test "returns a vector tile with the items" do
      insert(:geo_item,
        title: "Tile Item",
        geo_point: point(13.2679, 52.51),
        date_end: ~U[2026-03-31 22:30:00Z]
      )

      MapFeatures.refresh()

      {x, y} = tile_for(52.51, 13.2679, 15)
      tile = MapFeatures.tile(15, x, y)

      assert byte_size(tile) > 0
      # the layer name, the title and the date (in Berlin time) are part of the protobuf
      assert tile =~ "items"
      assert tile =~ "Tile Item"
      assert tile =~ "bis 01.04.2026"
    end
  end

  describe "tile/3 dates" do
    # every item in its own tile, so none is hidden by another at the same position
    defp tile_date(attrs) do
      {lng, lat} = {13.2679 + System.unique_integer([:positive]) * 0.01, 52.51}
      insert(:geo_item, Map.merge(%{geo_point: point(lng, lat)}, attrs))
      MapFeatures.refresh()

      {x, y} = tile_for(lat, lng, 16)
      MapFeatures.tile(16, x, y)
    end

    test "prefers the period, then the end, the start and the last update" do
      assert tile_date(%{
               date_start: ~U[2026-02-28 23:00:00Z],
               date_end: ~U[2026-12-31 12:00:00Z]
             }) =~
               "01.03.2026 – 31.12.2026"

      assert tile_date(%{
               date_start: ~U[2026-03-01 08:00:00Z],
               date_end: ~U[2026-03-01 18:00:00Z]
             }) =~
               "01.03.2026"

      assert tile_date(%{
               date_start: ~U[2026-03-01 08:00:00Z],
               date_updated: ~U[2026-09-01 08:00:00Z]
             }) =~
               "ab 01.03.2026"

      # the last update of the data only when there is nothing else
      assert tile_date(%{
               date_end: ~U[2025-02-08 12:00:00Z],
               date_updated: ~U[2026-09-01 08:00:00Z]
             }) =~
               "bis 08.02.2025"

      assert tile_date(%{date_updated: ~U[2026-09-01 08:00:00Z]}) =~ "aktualisiert 01.09.2026"
    end

    test "shows the publication date of news items" do
      published_at = DateTime.utc_now() |> DateTime.add(-2, :day) |> DateTime.truncate(:second)
      street = insert(:street, geo_point: point(13.2679, 52.51))

      insert(:news_item,
        published_at: published_at,
        geo_streets: [street],
        geo_street_numbers: [],
        geo_places: []
      )

      MapFeatures.refresh()

      {x, y} = tile_for(52.51, 13.2679, 16)

      expected =
        published_at |> DateTime.shift_zone!("Europe/Berlin") |> Calendar.strftime("%d.%m.%Y")

      assert MapFeatures.tile(16, x, y) =~ expected
    end
  end

  describe "bounds_around/4" do
    test "returns bounds around the center" do
      bounds = MapFeatures.bounds_around(@center, 15)

      assert bounds.west < @center.lng and bounds.east > @center.lng
      assert bounds.south < @center.lat and bounds.north > @center.lat
      assert_in_delta bounds.east - bounds.west, 1200 / (512 * :math.pow(2, 15)) * 360, 0.0001
    end
  end

  describe "version/0" do
    test "returns a short string" do
      assert MapFeatures.version() =~ ~r/^[\w-]{10}$/
    end
  end

  defp tile_for(lat, lng, zoom) do
    n = :math.pow(2, zoom)
    lat_rad = lat * :math.pi() / 180
    x = trunc((lng + 180) / 360 * n)
    y = trunc((1 - :math.log(:math.tan(lat_rad) + 1 / :math.cos(lat_rad)) / :math.pi()) / 2 * n)
    {x, y}
  end
end
