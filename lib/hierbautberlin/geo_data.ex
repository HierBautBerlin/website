defmodule Hierbautberlin.GeoData do
  import Ecto.Query, warn: false

  alias Hierbautberlin.Repo

  alias Hierbautberlin.GeoData.{
    AnalyzeText,
    GeoItem,
    GeoPlace,
    GeoStreet,
    GeoStreetNumber,
    NewsItem,
    Relevance,
    Source
  }

  @doc """
  All sources ordered by name, for the source filter on the map.
  """
  def list_sources do
    Repo.all(from source in Source, order_by: source.name)
  end

  @doc """
  The visible items for the sitemap, newest first: news since `since` and geo
  items that started, ended or were updated since then (so running projects
  stay in the sitemap). Returns `%{type: , id: , updated_at: }`.
  """
  def sitemap_items(since, limit \\ 20_000) do
    geo_items =
      from item in GeoItem,
        where: item.hidden == false,
        where:
          fragment(
            "greatest(?, ?, ?, ?) > ?",
            item.date_start,
            item.date_end,
            item.date_updated,
            item.inserted_at,
            ^since
          ),
        select: %{type: "geo_item", id: item.id, updated_at: item.updated_at}

    news_items =
      from item in NewsItem,
        where: item.hidden == false,
        where: item.published_at > ^since,
        select: %{type: "news_item", id: item.id, updated_at: item.updated_at}

    query =
      from item in subquery(union_all(geo_items, ^news_items)),
        order_by: [desc: item.updated_at],
        limit: ^limit

    Repo.all(query)
  end

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

  @doc """
  Finds streets by name for the search on the map, best matches first:

    1. the name is the search
    2. the name starts with the search ("unter den lin" -> "Unter den Linden")
    3. a word in the name starts with the search ("linden")
    4. the name contains the search ("torstr" -> "Wassertorstraße")
    5. the start of the name has a typo ("Sonenallee")

  Names are compared normalized (see the `search_normalize` SQL function), so
  "karl marx", "Friedrichstrasse" and "müllerstr." work. Within a group, streets
  with more house numbers (usually the more important ones) come first.
  """
  def search_street(search, limit \\ 10) do
    %{rows: rows} =
      Repo.query!(
        """
        WITH query AS MATERIALIZED (SELECT search_normalize($1) AS q)
        SELECT id FROM (
          SELECT s.id, s.name, s.district, s.street_number_count, CASE
              WHEN s.search_name = q THEN 0
              WHEN s.search_name LIKE q || '%' THEN 1
              WHEN s.search_name LIKE '% ' || q || '%' THEN 2
              WHEN length(q) >= 3 AND s.search_name LIKE '%' || q || '%' THEN 3
              WHEN length(q) >= 5
                AND levenshtein(q, left(s.search_name, length(q))) <= CASE WHEN length(q) >= 9 THEN 2 ELSE 1 END
                THEN 4
            END AS tier
          FROM geo_streets s, query
          WHERE q <> ''
        ) ranked
        WHERE tier IS NOT NULL
        ORDER BY tier, street_number_count DESC, name, district
        LIMIT $2
        """,
        [search, limit]
      )

    ids = List.flatten(rows)

    streets =
      from(street in GeoStreet, where: street.id in ^ids) |> Repo.all() |> Map.new(&{&1.id, &1})

    Enum.map(ids, &Map.fetch!(streets, &1))
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
    attrs = Map.merge(attrs, Relevance.for_geo_item(attrs))

    item
    |> GeoItem.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @doc """
  Hides the geo items of a source that are not part of the latest import anymore.

  Nothing is hidden when the import looks incomplete (no items or less than half
  of the currently visible items), so a broken data source doesn't hide everything.
  Returns the number of hidden items.
  """
  def hide_missing_geo_items(%Source{id: source_id}, imported_external_ids) do
    visible_query = from(item in GeoItem, where: item.source_id == ^source_id and not item.hidden)
    visible_count = Repo.aggregate(visible_query, :count)
    imported_count = length(Enum.uniq(imported_external_ids))

    if imported_count == 0 or imported_count < visible_count / 2 do
      0
    else
      {count, _} =
        visible_query
        |> where([item], item.external_id not in ^imported_external_ids)
        |> Repo.update_all(set: [hidden: true, updated_at: DateTime.utc_now(:second)])

      count
    end
  end

  @doc """
  Hides the geo items of a source outside of the bounding box
  `{min_lng, min_lat, max_lng, max_lat}`, e.g. items of an older import that
  covered all of Germany. Returns the number of hidden items.
  """
  def hide_geo_items_outside(%Source{id: source_id}, {min_lng, min_lat, max_lng, max_lat}) do
    {count, _} =
      from(item in GeoItem,
        where: item.source_id == ^source_id and not item.hidden,
        where:
          not fragment(
            "COALESCE(?, ?) && ST_MakeEnvelope(?, ?, ?, ?, 4326)",
            item.geo_point,
            item.geometry,
            ^min_lng,
            ^min_lat,
            ^max_lng,
            ^max_lat
          )
      )
      |> Repo.update_all(set: [hidden: true, updated_at: DateTime.utc_now(:second)])

    count
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

  def get_point(%NewsItem{geo_points: item}) when not is_nil(item) do
    %{coordinates: [{lng, lat} | _tail]} = item
    %{lat: lat, lng: lng}
  end

  def get_point(%NewsItem{geometries: item}) when not is_nil(item) do
    %{geometries: [geometry | _tail]} = item
    %{coordinates: {lng, lat}} = Geo.Turf.Measure.center(geometry)

    %{lat: lat, lng: lng}
  end

  def get_point(%struct{geo_point: %Geo.Point{coordinates: {lng, lat}}})
      when struct in [GeoStreet, GeoStreetNumber, GeoPlace] do
    %{lat: lat, lng: lng}
  end

  def get_point(_item) do
    %{lat: nil, lng: nil}
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

  @doc """
  Stores the house numbers `analyze_text/2` interpolated and returns them
  together with the ones that were found directly.

  Interpolated numbers have no `external_id`, so the OSM import drops them again
  as soon as no news item links them - for example because OSM has learned the
  real address in the meantime.
  """
  def store_interpolated_numbers(result) do
    result.street_numbers ++ Enum.map(result.interpolated, &store_interpolated_number/1)
  end

  defp store_interpolated_number(attrs) do
    existing =
      Repo.one(
        from number in GeoStreetNumber,
          where:
            number.geo_street_id == ^attrs.geo_street_id and
              number.number == ^attrs.number and number.interpolated
      )

    (existing || %GeoStreetNumber{})
    |> Ecto.Changeset.change(%{
      geo_street_id: attrs.geo_street_id,
      number: attrs.number,
      zip: attrs.zip,
      ortsteil: attrs.ortsteil,
      geo_point: attrs.geo_point,
      interpolated: true
    })
    |> Repo.insert_or_update!()
  end

  def upsert_news_item!(attrs, full_text, districts) do
    districts = districts |> List.wrap() |> Enum.filter(&is_binary/1)
    result = analyze_text(full_text, %{districts: districts})

    item = get_news_item_with_external_id(attrs[:source_id], attrs[:external_id]) || %NewsItem{}
    source = attrs[:source_id] && get_source!(attrs[:source_id])

    attrs =
      attrs
      |> Map.merge(%{full_text: full_text, districts: districts})
      |> Map.merge(
        Relevance.for_news_item(
          attrs[:title],
          full_text || attrs[:content],
          attrs[:published_at],
          source && source.short_name
        )
      )

    item
    |> NewsItem.changeset(attrs)
    |> Repo.insert_or_update!()
    |> Repo.preload([:geo_streets, :geo_street_numbers, :geo_places])
    |> NewsItem.change_associations(
      geo_streets: result.streets,
      geo_street_numbers: store_interpolated_numbers(result),
      context_streets: result.context_streets,
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
        where: item.inserted_at >= ^since and not item.hidden,
        where: ^conditions,
        order_by: [:inserted_at, :id]

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
        where: item.inserted_at >= ^since and not item.hidden,
        where: ^conditions,
        order_by: [:inserted_at, :id]

    Repo.all(query)
  end
end
