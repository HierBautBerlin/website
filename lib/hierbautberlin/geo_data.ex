defmodule Hierbautberlin.GeoData do
  import Ecto.Query, warn: false

  alias Hierbautberlin.{PostgresQueryHelper, Repo}

  alias Hierbautberlin.GeoData.{
    AnalyzeText,
    GeoItem,
    GeoPlace,
    GeoPosition,
    GeoStreet,
    GeoStreetNumber,
    NewsItem,
    Source
  }

  def get_source!(id) do
    Repo.get!(Source, id)
  end

  def get_source_by_short_name(short_name) do
    Repo.get_by(Source, short_name: short_name)
  end

  def upsert_source(attrs \\ %{}) do
    source = get_source_by_short_name(attrs[:short_name]) || %Source{}

    source
    |> Source.changeset(attrs)
    |> Repo.insert_or_update()
  end

  def get_geo_street!(id) do
    Repo.get!(GeoStreet, id)
  end

  def get_geo_streets(ids) do
    query =
      from(
        street in GeoStreet,
        where: street.id in ^ids
      )

    Repo.all(query)
  end

  def get_geo_street_number!(id) do
    Repo.get!(GeoStreetNumber, id)
  end

  def get_geo_street_numbers(ids) do
    query =
      from(
        street_number in GeoStreetNumber,
        where: street_number.id in ^ids
      )

    Repo.all(query)
  end

  def search_street(search) do
    if String.length(search) < 3 do
      do_simple_street_search(search)
    else
      do_complex_street_search(search)
    end
    |> Repo.all()
  end

  defp do_simple_street_search(search) do
    search_query = "#{search}%"

    from(
      entry in GeoStreet,
      where: ilike(entry.name, ^search_query),
      order_by: [desc: entry.street_number_count],
      limit: 10
    )
  end

  defp do_complex_street_search(search) do
    downcase_search = String.downcase(search)
    formatted_search = PostgresQueryHelper.format_search_query(search)

    from(
      entry in GeoStreet,
      where:
        fragment(
          "? in (select id from geo_streets where (fulltext_search @@ to_tsquery('german', unaccent(?)) or name ilike ?))",
          entry.id,
          ^formatted_search,
          ^"%#{search}%"
        ),
      order_by: [
        desc: entry.street_number_count,
        asc: fragment("levenshtein(?, lower(?), 1, 10, 20), name", ^downcase_search, entry.name)
      ],
      limit: 10
    )
  end

  def get_geo_place!(id) do
    Repo.get!(GeoPlace, id)
  end

  def get_geo_places(ids) do
    query =
      from(
        geo_place in GeoPlace,
        where: geo_place.id in ^ids
      )

    Repo.all(query)
  end

  def get_news_item!(id) do
    Repo.get!(NewsItem, id)
    |> Repo.preload([:source])
  end

  def get_news_item_with_external_id(source_id, external_id) do
    Repo.get_by(NewsItem, source_id: source_id, external_id: external_id)
    |> Repo.preload([:source])
  end

  def get_geo_item!(id) do
    Repo.get!(GeoItem, id)
    |> Repo.preload([:source])
  end

  def create_geo_item(attrs \\ %{}) do
    %GeoItem{}
    |> GeoItem.changeset(attrs)
    |> Repo.insert()
  end

  def get_geo_item_with_external_id(source_id, external_id) do
    Repo.get_by(GeoItem, source_id: source_id, external_id: external_id)
    |> Repo.preload(:source)
  end

  def change_geo_item(%GeoItem{} = geo_item), do: GeoItem.changeset(geo_item, %{})

  def upsert_geo_item(attrs \\ %{}) do
    item = get_geo_item_with_external_id(attrs[:source_id], attrs[:external_id]) || %GeoItem{}

    item
    |> GeoItem.changeset(attrs)
    |> Repo.insert_or_update()
  end

  def get_point(geo_item)

  def get_point(%GeoItem{geo_point: item}) when not is_nil(item) do
    %{coordinates: {lng, lat}} = item
    %{lat: lat, lng: lng}
  end

  def get_point(%GeoItem{geometry: geometry}) when not is_nil(geometry) do
    %{coordinates: {lng, lat}} = Geo.Turf.Measure.center(geometry)
    %{lat: lat, lng: lng}
  end

  def get_point(%GeoPosition{geopoint: item}) when not is_nil(item) do
    %{coordinates: {lng, lat}} = item
    %{lat: lat, lng: lng}
  end

  def get_point(%GeoPosition{geometry: geometry}) when not is_nil(geometry) do
    %{coordinates: {lng, lat}} = Geo.Turf.Measure.center(geometry)
    %{lat: lat, lng: lng}
  end

  def get_point(%NewsItem{geo_points: item}) when not is_nil(item) do
    %{coordinates: [{lng, lat} | _tail]} = item
    %{lat: lat, lng: lng}
  end

  def get_point(%NewsItem{geometries: item}) when not is_nil(item) do
    %{geometries: [geometry | _tail]} = item
    %{coordinates: {lng, lat}} = Geo.Turf.Measure.center(geometry)

    %{lat: lat, lng: lng}
  end

  def get_point(_item) do
    %{lat: nil, lng: nil}
  end

  def get_items_near(lat, lng, count \\ 10) do
    items = GeoItem.get_near(lat, lng, count) ++ NewsItem.get_near(lat, lng, count)

    items
    |> remove_old_items()
    |> sort_by_relevance(%{lat: lat, lng: lng})
    |> Enum.take(count)
  end

  defp remove_old_items(items) do
    five_years_ago = Timex.shift(Timex.today(), years: -5)

    Enum.filter(items, fn item ->
      item.newest_date == nil || Timex.after?(item.newest_date, five_years_ago)
    end)
  end

  defp sort_by_relevance(items, coordinates) do
    {new_items, old_items} =
      items
      |> remove_empty_positions()
      |> split_items_by_date()

    sort_by_date_and_distance(new_items, coordinates) ++
      sort_by_date_and_distance(old_items, coordinates)
  end

  defp remove_empty_positions(items) do
    Enum.filter(items, fn item ->
      !Enum.empty?(item.positions)
    end)
  end

  defp split_items_by_date(items) do
    Enum.split_with(items, fn item ->
      item.newest_date && abs(Timex.diff(Timex.now(), item.newest_date, :weeks)) < 6
    end)
  end

  def sort_by_date_and_distance(items, %{lat: lat, lng: lng}) do
    Enum.sort_by(items, fn item ->
      months_difference =
        Timex.diff(
          Timex.now(),
          item.newest_date || Timex.shift(Timex.today(), months: -3),
          :months
        )

      distance =
        item.positions
        |> Enum.map(fn position ->
          %{lat: item_lat, lng: item_lng} = get_point(position)

          Geo.Turf.Measure.distance(
            %Geo.Point{coordinates: {lng, lat}},
            %Geo.Point{coordinates: {item_lng, item_lat}},
            :meters
          )
        end)
        |> Enum.sort()
        |> List.first()

      push_factor =
        if item.participation_open do
          30
        else
          0
        end

      distance / 10 + months_difference - push_factor
    end)
  end

  def with_news(item) do
    Repo.preload(item, news_items: [:source])
  end

  def with_geo_street(item) do
    Repo.preload(item, :geo_street)
  end

  def analyze_text(text, options \\ %{}) do
    AnalyzeText.analyze_text(text, options)
  end

  def upsert_news_item!(attrs, full_text, districts) do
    result = analyze_text(full_text, %{districts: districts})

    item = get_news_item_with_external_id(attrs[:source_id], attrs[:external_id]) || %NewsItem{}

    item
    |> NewsItem.changeset(attrs)
    |> Repo.insert_or_update!()
    |> Repo.preload([:geo_streets, :geo_street_numbers, :geo_places])
    |> NewsItem.change_associations(
      geo_streets: result.streets,
      geo_street_numbers: result.street_numbers,
      geo_places: result.places
    )
    |> Repo.update!()
  end

  def get_geo_items_for_locations_since(locations, since) do
    conditions = false

    conditions =
      Enum.reduce(locations, conditions, fn %{location: {lat, lng}, radius: radius}, conditions ->
        filter_conditions =
          dynamic(
            [item],
            fragment(
              "ST_DWITHIN(COALESCE(geometry, geo_point), ST_MakePoint(?, ?)::geography, ?)",
              ^lng,
              ^lat,
              ^radius
            )
          )

        if conditions do
          dynamic([item], ^filter_conditions or ^conditions)
        else
          dynamic([item], ^filter_conditions)
        end
      end)

    query =
      from item in GeoItem,
        where: item.inserted_at >= ^since,
        where: ^conditions,
        order_by: :inserted_at

    Repo.all(query)
  end

  def get_news_items_for_locations_since(locations, since) do
    conditions = false

    conditions =
      Enum.reduce(locations, conditions, fn %{location: {lat, lng}, radius: radius}, conditions ->
        filter_conditions =
          dynamic(
            [item],
            fragment(
              "(ST_DWITHIN(geometries, ST_MakePoint(?, ?)::geography, ?) OR ST_DWITHIN(geo_points, ST_MakePoint(?, ?)::geography, ?))",
              ^lng,
              ^lat,
              ^radius,
              ^lng,
              ^lat,
              ^radius
            )
          )

        if conditions do
          dynamic([item], ^filter_conditions or ^conditions)
        else
          dynamic([item], ^filter_conditions)
        end
      end)

    query =
      from item in NewsItem,
        where: item.inserted_at >= ^since,
        where: ^conditions,
        order_by: :inserted_at

    Repo.all(query)
  end
end
