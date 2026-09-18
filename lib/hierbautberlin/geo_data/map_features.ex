defmodule Hierbautberlin.GeoData.MapFeatures do
  @moduledoc """
  Everything the map needs, backed by the `map_features` materialized view.

    * `tile/3` renders Mapbox vector tiles (MVT) with all visible features.
    * `list_items/2` returns the most relevant items for the list next to the map.
    * `refresh/0` needs to be called after data changed (e.g. after imports).
  """

  import Ecto.Query, warn: false

  alias Hierbautberlin.GeoData.{
    GeoItem,
    GeoMapItem,
    GeoPlace,
    GeoStreet,
    GeoStreetNumber,
    NewsItem,
    Relevance
  }

  alias Hierbautberlin.Repo

  # Features below this zoom level are only drawn as points
  @full_geometry_zoom 13
  # Below this zoom level only recent items (or items with open participation) are shown
  @recent_only_zoom 12
  @min_zoom 11

  # Part of the tile version, so browsers load new tiles instead of cached ones
  # when the content of the tiles changes. Increase it when changing tile/3.
  @tile_format 4
  @max_zoom 22

  # Entries that are finished or whose date is longer ago than this are "old and
  # done", the filter of the list can leave them out (also in interactiveMap.ts)
  @outdated_after "1 year"

  # The list does not need the (big) geometry columns
  @geo_item_list_fields GeoItem.__schema__(:fields) -- [:geo_point, :geometry]
  @news_item_list_fields NewsItem.__schema__(:fields) -- [:geo_points, :geometries]

  def min_zoom, do: @min_zoom

  @doc """
  Refreshes the materialized view and bumps the version used for tile caching.
  """
  def refresh do
    Repo.query!("REFRESH MATERIALIZED VIEW CONCURRENTLY map_features", [], timeout: :infinity)
    :persistent_term.erase({__MODULE__, :version})
    :ok
  end

  @doc """
  A version string that changes whenever the map data changes. Used in tile
  URLs, so tiles can be cached by the browser.
  """
  def version do
    case :persistent_term.get({__MODULE__, :version}, nil) do
      {version, expires_at} when expires_at > 0 ->
        if System.monotonic_time(:second) < expires_at, do: version, else: load_version()

      _ ->
        load_version()
    end
  end

  defp load_version do
    %{rows: [row]} =
      Repo.query!(
        "SELECT (SELECT count(*) FROM map_features), (SELECT max(updated_at) FROM geo_items), " <>
          "(SELECT max(updated_at) FROM news_items)"
      )

    version =
      :crypto.hash(:md5, inspect({@tile_format, row}))
      |> Base.url_encode64(padding: false)
      |> binary_part(0, 10)

    :persistent_term.put({__MODULE__, :version}, {version, System.monotonic_time(:second) + 60})
    version
  end

  @doc """
  Returns the vector tile for the given tile coordinates as binary. The only
  layer is called `items`.
  """
  def tile(z, x, y) when z < @min_zoom or z > @max_zoom or x < 0 or y < 0, do: <<>>

  def tile(z, x, y) do
    %{rows: [[tile]]} =
      Repo.query!(
        """
        WITH bounds AS (
          SELECT ST_TileEnvelope($1, $2, $3) AS envelope,
                 ST_Transform(ST_TileEnvelope($1, $2, $3, margin => 0.015625), 4326) AS envelope_4326
        ),
        features AS (
          SELECT DISTINCT ON (f.position_type, f.position_id, f.draw)
            f.item_type,
            f.item_id,
            f.title,
            f.draw,
            f.participation_open,
            f.source_id,
            #{outdated_sql("f")} AS outdated,
            CASE WHEN f.draw IN ('line', 'polygon') THEN s.background_color ELSE s.color END AS color,
            ST_AsMVTGeom(ST_Transform(f.geom, 3857), bounds.envelope, 4096, 64, true) AS geom
          FROM map_features f
          JOIN sources s ON s.id = f.source_id
          CROSS JOIN bounds
          WHERE f.geom && bounds.envelope_4326
            AND (f.newest_date IS NULL OR f.newest_date > now() - interval '5 years')
            AND CASE
              WHEN $1 >= $4 THEN f.draw <> 'center'
              ELSE f.draw IN ('circle', 'center')
            END
            AND (
              $1 >= $5
              OR f.participation_open
              OR f.newest_date > now() - interval '1 year'
            )
          ORDER BY f.position_type, f.position_id, f.draw, f.newest_date DESC NULLS LAST
        ),
        -- the date for the tooltip, only for the features in the tile
        labeled AS (
          SELECT features.*, #{date_label_sql("g", "n")} AS date
          FROM features
          LEFT JOIN geo_items g ON features.item_type = 'geo_item' AND g.id = features.item_id
          LEFT JOIN news_items n ON features.item_type = 'news_item' AND n.id = features.item_id
          WHERE features.geom IS NOT NULL
        )
        SELECT ST_AsMVT(labeled.*, 'items', 4096, 'geom') FROM labeled
        """,
        [z, x, y, @full_geometry_zoom, @recent_only_zoom]
      )

    tile || <<>>
  end

  # Finished entries and entries whose date is more than a year ago. The client
  # hides them when "Alte und erledigte Einträge" is unchecked, entries without
  # a date stay visible.
  defp outdated_sql(features) do
    "(#{features}.finished OR " <>
      "coalesce(#{features}.newest_date < now() - interval '#{@outdated_after}', false))"
  end

  # The most meaningful date of an item as text (Berlin time): the publication
  # date of news, the period of geo items ("01.03.2026 – 31.12.2026"), otherwise
  # "bis …" or "ab …" and only as last resort the last update of the data.
  defp date_label_sql(geo, news) do
    day = fn column -> "to_char(#{column} AT TIME ZONE 'Europe/Berlin', 'DD.MM.YYYY')" end

    """
    CASE
      WHEN #{news}.published_at IS NOT NULL
        THEN #{day.("#{news}.published_at AT TIME ZONE 'UTC'")}
      WHEN #{geo}.date_start IS NOT NULL AND #{geo}.date_end IS NOT NULL
        AND #{day.("#{geo}.date_start")} <> #{day.("#{geo}.date_end")}
        THEN #{day.("#{geo}.date_start")} || ' – ' || #{day.("#{geo}.date_end")}
      WHEN #{geo}.date_start IS NOT NULL AND #{geo}.date_end IS NOT NULL
        THEN #{day.("#{geo}.date_start")}
      WHEN #{geo}.date_end IS NOT NULL THEN 'bis ' || #{day.("#{geo}.date_end")}
      WHEN #{geo}.date_start IS NOT NULL THEN 'ab ' || #{day.("#{geo}.date_start")}
      WHEN #{geo}.date_updated IS NOT NULL THEN 'aktualisiert ' || #{day.("#{geo}.date_updated")}
    END
    """
  end

  @doc """
  Returns the most relevant items within the bounds, sorted by relevance.

  The score is `importance * time factor * distance factor`, see
  `Hierbautberlin.GeoData.Relevance`. The distance factor is 1 at the center
  and 0.5 at a quarter of the viewport diagonal, so when zoomed out important
  items further away can still be on top.

  Options:
    * `:limit` - the maximum number of items (default 100)
    * `:hidden_sources` - ids of sources whose items are left out
    * `:query` - only items with this text in the title, subtitle or description
    * `:show_old` - when false, finished entries and entries older than a year
      are left out (default true)
  """
  def list_items(
        %{west: west, south: south, east: east, north: north},
        %{lat: lat, lng: lng},
        opts \\ []
      ) do
    limit = Keyword.get(opts, :limit, 100)
    hidden_sources = Keyword.get(opts, :hidden_sources, [])
    pattern = like_pattern(Keyword.get(opts, :query))
    show_old = Keyword.get(opts, :show_old, true)

    %{rows: rows} =
      Repo.query!(
        """
        WITH matching AS MATERIALIZED (
          -- same expressions as the trigram indexes (migration 20260915120000)
          SELECT 'geo_item' AS item_type, id AS item_id FROM geo_items
          WHERE $9::text IS NOT NULL
            AND (coalesce(title, '') || ' ' || coalesce(subtitle, '') || ' ' || coalesce(description, '')) ILIKE $9
          UNION ALL
          SELECT 'news_item', id FROM news_items
          WHERE $9::text IS NOT NULL
            AND (coalesce(title, '') || ' ' || coalesce(content, '')) ILIKE $9
        ),
        center AS (
          SELECT ST_SetSRID(ST_MakePoint($5, $6), 4326) AS point,
                 ST_MakeEnvelope($1, $2, $3, $4, 4326) AS envelope,
                 greatest(
                   ST_Distance(ST_MakePoint($1, $2)::geography, ST_MakePoint($3, $4)::geography) / 4,
                   50
                 ) AS radius
        ),
        nearest AS (
          SELECT f.item_type, f.item_id, f.newest_date,
                 -- planar distance in degrees, roughly converted to meters (good enough for sorting)
                 (f.geom <-> center.point) * 111320 * cos(radians($6)) AS distance
          FROM map_features f
          CROSS JOIN center
          WHERE f.geom && center.envelope
            AND (f.newest_date IS NULL OR f.newest_date > now() - interval '5 years')
            AND NOT (f.source_id = ANY($8::bigint[]))
            AND ($10::boolean OR NOT #{outdated_sql("f")})
            AND ($9::text IS NULL OR (f.item_type, f.item_id) IN (SELECT item_type, item_id FROM matching))
          ORDER BY f.geom <-> center.point
          LIMIT 2000
        ),
        -- important items further away that are not among the nearest features
        important AS (
          SELECT f.item_type, f.item_id, f.newest_date,
                 (f.geom <-> center.point) * 111320 * cos(radians($6)) AS distance
          FROM (
            SELECT 'geo_item' AS item_type, id AS item_id FROM geo_items
            WHERE importance >= 2
              AND relevance_time_factor(relevant_from, relevant_until, relevance_half_life) > 0.5
            UNION ALL
            SELECT 'news_item', id FROM news_items
            WHERE (importance >= 2
                AND relevance_time_factor(relevant_from, relevant_until, relevance_half_life) > 0.5)
              OR (importance * #{Relevance.fresh_boost()} >= 2
                AND #{Relevance.fresh_news_sql("published_at", "source_id")}
                AND relevance_time_factor(relevant_from, relevant_until, relevance_half_life)
                  * #{Relevance.fresh_boost()} > 0.5)
          ) i
          CROSS JOIN center
          CROSS JOIN LATERAL (
            SELECT * FROM map_features f
            WHERE f.item_type = i.item_type AND f.item_id = i.item_id AND f.geom && center.envelope
              AND NOT (f.source_id = ANY($8::bigint[]))
              AND ($10::boolean OR NOT #{outdated_sql("f")})
              AND ($9::text IS NULL OR (f.item_type, f.item_id) IN (SELECT item_type, item_id FROM matching))
          ) f
        ),
        items AS (
          SELECT item_type, item_id, max(newest_date) AS newest_date, min(distance) AS distance
          FROM (SELECT * FROM nearest UNION ALL SELECT * FROM important) candidates
          GROUP BY item_type, item_id
        ),
        scored AS (
          SELECT items.*,
                 r.importance
                   -- news items with long lists of addresses are not about a place
                   * CASE WHEN items.item_type = 'news_item' AND (
                       SELECT count(*) FROM map_features f
                       WHERE f.item_type = 'news_item' AND f.item_id = items.item_id
                     ) > 30 THEN 0.3 ELSE 1 END
                   * CASE WHEN r.fresh THEN #{Relevance.fresh_boost()} ELSE 1 END
                   * relevance_time_factor(r.relevant_from, r.relevant_until, r.relevance_half_life)
                   / (1 + power(items.distance / center.radius, 2)) AS score
          FROM items
          CROSS JOIN center
          #{relevance_join("items")}
        )
        SELECT item_type, item_id
        FROM scored
        ORDER BY score DESC, newest_date DESC NULLS LAST, item_type, item_id
        LIMIT $7
        """,
        [west, south, east, north, lng, lat, limit, hidden_sources, pattern, show_old]
      )

    load_items(rows)
  end

  # "Baum" -> "%Baum%", LIKE wildcards in the query are escaped
  defp like_pattern(query) when is_binary(query) do
    case String.trim(query) do
      "" -> nil
      text -> "%" <> String.replace(text, ~r/[\\%_]/, "\\\\\\0") <> "%"
    end
  end

  defp like_pattern(_query), do: nil

  # Joins the relevance columns of the geo or news item as `r`, `fresh` is true
  # for press releases of the last weeks
  defp relevance_join(table) do
    """
    CROSS JOIN LATERAL (
      SELECT importance, relevant_from, relevant_until, relevance_half_life, false AS fresh
      FROM geo_items WHERE #{table}.item_type = 'geo_item' AND id = #{table}.item_id
      UNION ALL
      SELECT importance, relevant_from, relevant_until, relevance_half_life,
             #{Relevance.fresh_news_sql("published_at", "source_id")}
      FROM news_items WHERE #{table}.item_type = 'news_item' AND id = #{table}.item_id
    ) r
    """
  end

  defp load_items(rows) do
    ids_by_type = Enum.group_by(rows, &Enum.at(&1, 0), &Enum.at(&1, 1))

    geo_items =
      from(item in GeoItem,
        where: item.id in ^Map.get(ids_by_type, "geo_item", []),
        select: struct(item, ^@geo_item_list_fields)
      )
      |> Repo.all()
      |> Repo.preload(:source)
      |> Map.new(&{{"geo_item", &1.id}, to_map_item(&1)})

    news_items =
      from(item in NewsItem,
        where: item.id in ^Map.get(ids_by_type, "news_item", []),
        select: struct(item, ^@news_item_list_fields)
      )
      |> Repo.all()
      |> Repo.preload(:source)
      |> Map.new(&{{"news_item", &1.id}, to_map_item(&1)})

    items = Map.merge(geo_items, news_items)

    rows
    |> Enum.map(fn [type, id] -> Map.get(items, {type, id}) end)
    |> Enum.reject(&is_nil/1)
  end

  defp to_map_item(%GeoItem{} = item) do
    %GeoMapItem{
      type: :geo_item,
      id: item.id,
      title: item.title,
      subtitle: item.subtitle,
      description: truncate(item.description),
      newest_date: GeoItem.newest_date(item),
      source: item.source,
      url: item.url,
      participation_open: item.participation_open,
      item: item
    }
  end

  defp to_map_item(%NewsItem{} = item) do
    %GeoMapItem{
      type: :news_item,
      id: item.id,
      title: item.title,
      description: truncate(item.content),
      newest_date: item.published_at,
      source: item.source,
      url: item.url,
      participation_open: false,
      item: item
    }
  end

  # The list only shows the first lines of the description
  defp truncate(nil), do: nil

  defp truncate(text) do
    if String.length(text) > 300, do: String.slice(text, 0, 300) <> "…", else: text
  end

  @shape_columns %{
    GeoItem => {"geo_items", "geometry", "geo_point"},
    NewsItem => {"news_items", "geometries", "geo_points"},
    GeoStreet => {"geo_streets", "geometry", "geo_point"},
    GeoPlace => {"geo_places", "geometry", "geo_point"},
    GeoStreetNumber => {"geo_street_numbers", "NULL::geometry", "geo_point"}
  }
  @shape_tolerance 0.00002
  @max_shape_bytes 100_000

  @doc """
  The shape of an entry for the small map in the details as GeoJSON
  FeatureCollection (JSON string), nil when it has no location. Every feature
  has a `draw` property: `polygon`, `line` or `point`.

  Lines and polygons are simplified (about 2 m). When they are still too big
  (e.g. a news item about hundreds of streets), only the points are returned.
  """
  def details_shape(%struct{id: id}) when is_integer(id) do
    case Map.fetch(@shape_columns, struct) do
      {:ok, {table, shape, points}} -> load_details_shape(table, shape, points, id)
      :error -> nil
    end
  end

  def details_shape(_item), do: nil

  defp load_details_shape(table, shape, points, id) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT parts.draw, ST_AsGeoJSON(parts.geom, 6)
        FROM (SELECT #{shape} AS shape, #{points} AS points FROM #{table} WHERE id = $1) item,
        LATERAL (VALUES
          (1, 'polygon', ST_SimplifyPreserveTopology(ST_CollectionExtract(item.shape, 3), $2)),
          (2, 'line', ST_SimplifyPreserveTopology(ST_CollectionExtract(item.shape, 2), $2)),
          (3, 'point', ST_CollectionExtract(ST_Collect(ST_CollectionExtract(item.shape, 1), item.points), 1))
        ) AS parts(position, draw, geom)
        WHERE parts.geom IS NOT NULL AND NOT ST_IsEmpty(parts.geom)
        ORDER BY parts.position
        """,
        [id, @shape_tolerance]
      )

    rows =
      if rows |> Enum.map(fn [_draw, json] -> byte_size(json) end) |> Enum.sum() >
           @max_shape_bytes,
         do: Enum.filter(rows, fn [draw, _json] -> draw == "point" end),
         else: rows

    if rows != [] do
      Jason.encode!(%{
        type: "FeatureCollection",
        features:
          Enum.map(rows, fn [draw, json] ->
            %{type: "Feature", properties: %{draw: draw}, geometry: Jason.Fragment.new(json)}
          end)
      })
    end
  end

  @doc """
  Returns the bounds of a viewport of `width` x `height` pixels around the
  center at the given (web mercator) zoom level.
  """
  def bounds_around(%{lat: lat, lng: lng}, zoom, width \\ 1200, height \\ 900) do
    world_size = 512 * :math.pow(2, zoom)
    {x, y} = project(lng, lat, world_size)

    {west, north} = unproject(x - width / 2, y - height / 2, world_size)
    {east, south} = unproject(x + width / 2, y + height / 2, world_size)

    %{west: west, south: south, east: east, north: north}
  end

  defp project(lng, lat, world_size) do
    sin = :math.sin(lat * :math.pi() / 180)
    x = (lng + 180) / 360 * world_size
    y = (0.5 - :math.log((1 + sin) / (1 - sin)) / (4 * :math.pi())) * world_size
    {x, y}
  end

  defp unproject(x, y, world_size) do
    lng = x / world_size * 360 - 180
    n = :math.pi() - 2 * :math.pi() * y / world_size
    lat = 180 / :math.pi() * :math.atan(0.5 * (:math.exp(n) - :math.exp(-n)))
    {lng, lat}
  end
end
