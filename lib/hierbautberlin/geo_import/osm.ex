defmodule Hierbautberlin.GeoImport.OSM do
  @moduledoc """
  Imports streets and street numbers from an OpenStreetMap extract.

  1. `ogr2ogr` loads points, lines and multipolygons into the `osm_import` schema
     (see `priv/osm/osmconf.ini` for the extracted tags).
  2. SQL builds staging tables: city and district boundaries, addresses (nodes
     *and* buildings), streets (real highway geometries, split by district) and
     places (green spaces, squares and lakes, see `@place_types`).
  3. Streets are upserted by `(name, district)` and street numbers by
     `external_id`, so ids and the links to news items survive re-imports.
     Streets and numbers that vanished from OSM are only deleted when no news
     item links to them.
  """

  require Logger

  alias Hierbautberlin.Repo

  @schema "osm_import"

  # Named ways with these highway tags become streets. Other named highways
  # (footways, paths, ...) are only used if an address references their name.
  @street_highways ~w(motorway motorway_link trunk trunk_link primary primary_link secondary
    secondary_link tertiary tertiary_link unclassified residential living_street pedestrian
    service road busway)

  # Named areas people talk about: green spaces, squares, standing water and
  # landmarks. They are the places texts are matched against, so the tags are
  # narrow on purpose - every name in the index can also be a false match.
  # Not included: allotments and sports grounds (many, with generic names), the
  # parts of a botanical garden ("Arzneipflanzen", they are gardens as well, but
  # neither public nor a tourism destination), flowing water, cemeteries, and
  # everything that is a building or a POI.
  @place_types [
    {"Park",
     """
     m.leisure IN ('park', 'nature_reserve', 'common')
       OR (m.leisure = 'garden'
           AND (m.tourism IS NOT NULL OR m.garden_type = 'public'))
       OR m.landuse IN ('recreation_ground', 'village_green', 'forest')
       -- a park that is being built, like the Spreepark
       OR (m.landuse = 'construction'
           AND m.construction IN ('park', 'garden', 'recreation_ground'))
     """},
    {"Square", "m.place = 'square'"},
    {"Landmark", "m.tourism = 'attraction'"},
    {"Water",
     """
     m."natural" = 'water'
       AND coalesce(m.water, 'lake') NOT IN
           ('river', 'canal', 'stream', 'ditch', 'drain', 'moat', 'lock', 'wastewater')
     """}
  ]

  # The water basins and ponds inside a park have descriptive names
  # ("Wasserbecken", "Ententeich") that match any text about the park
  @min_water_area 5000

  @place_type_sql "CASE " <>
                    Enum.map_join(@place_types, " ", fn {type, condition} ->
                      "WHEN #{String.trim(condition)} THEN '#{type}'"
                    end) <> " END"

  @doc """
  Runs the whole import for the given `.osm.pbf` (or `.osm`) file and returns
  statistics about what changed.
  """
  def import(file, opts \\ []) do
    city = Keyword.get(opts, :city, "Berlin")

    load_file(file)
    build_staging_tables(city)

    before = counts()
    changes = upsert()
    after_import = counts()

    stats = %{before: before, after: after_import, changes: changes, staging: staging_counts()}
    Logger.info("OSM import finished: #{inspect(stats)}")
    stats
  end

  @doc """
  Loads the OSM file into the `osm_import` schema using `ogr2ogr`.
  """
  def load_file(file) do
    unless File.exists?(file), do: raise("OSM file #{file} does not exist")

    # ogr2ogr uses its own connection, so the schema has to be created outside of
    # any transaction the repo might be in (e.g. in tests)
    {:ok, conn} = Postgrex.start_link(connection_options() ++ [pool_size: 1])
    Postgrex.query!(conn, "CREATE SCHEMA IF NOT EXISTS #{@schema}", [])
    GenServer.stop(conn)

    {connection, password} = ogr_connection()

    args = [
      "-f",
      "PostgreSQL",
      connection,
      file,
      "points",
      "lines",
      "multipolygons",
      "-overwrite",
      "-lco",
      "GEOMETRY_NAME=geom",
      "-lco",
      "SPATIAL_INDEX=GIST",
      "--config",
      "PG_USE_COPY",
      "YES",
      "-gt",
      "100000"
    ]

    env = [
      {"OSM_CONFIG_FILE", Application.app_dir(:hierbautberlin, "priv/osm/osmconf.ini")},
      {"PGPASSWORD", password || ""}
    ]

    case System.cmd("ogr2ogr", args, env: env, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> raise "ogr2ogr failed with status #{status}: #{output}"
    end
  end

  defp connection_options do
    config = Repo.config()

    if url = config[:url] do
      uri = URI.parse(url)
      [username, password] = String.split(uri.userinfo || ":", ":", parts: 2)

      [
        hostname: uri.host,
        port: uri.port || 5432,
        username: URI.decode(username),
        password: URI.decode(password),
        database: String.trim_leading(uri.path, "/")
      ]
    else
      Keyword.take(config, [:hostname, :port, :username, :password, :database])
    end
  end

  defp ogr_connection do
    config = connection_options()

    connection =
      [
        "host=#{config[:hostname] || "localhost"}",
        "port=#{config[:port] || 5432}",
        "user=#{config[:username]}",
        "dbname=#{config[:database]}",
        "active_schema=#{@schema}"
      ]
      |> Enum.join(" ")

    {"PG:" <> connection, config[:password]}
  end

  @doc """
  Builds the staging tables `city`, `districts`, `ortsteile`, `postcodes`,
  `addresses`, `streets` and `places` from the loaded OSM data.
  """
  def build_staging_tables(city) do
    for table <- ~w(city districts ortsteile postcodes addresses street_parts streets places) do
      query!("DROP TABLE IF EXISTS #{@schema}.#{table}")
    end

    query!(
      """
      CREATE TABLE #{@schema}.city AS
      SELECT ST_Union(geom) AS geom FROM #{@schema}.multipolygons
      WHERE boundary = 'administrative' AND admin_level = '4' AND name = $1
      """,
      [city]
    )

    for {table, admin_level} <- [{"districts", "9"}, {"ortsteile", "10"}] do
      query!(
        """
        CREATE TABLE #{@schema}.#{table} AS
        SELECT m.name, ST_Subdivide(m.geom, 64) AS geom
        FROM #{@schema}.multipolygons m, #{@schema}.city c
        WHERE m.boundary = 'administrative' AND m.admin_level = $1 AND m.name IS NOT NULL
          AND ST_Within(ST_PointOnSurface(m.geom), c.geom)
        """,
        [admin_level]
      )

      query!("CREATE INDEX ON #{@schema}.#{table} USING GIST (geom)")
    end

    query!("""
    CREATE TABLE #{@schema}.postcodes AS
    SELECT postal_code, ST_Subdivide(geom, 64) AS geom FROM #{@schema}.multipolygons
    WHERE boundary = 'postal_code' AND postal_code IS NOT NULL
    """)

    query!("CREATE INDEX ON #{@schema}.postcodes USING GIST (geom)")

    build_addresses()
    build_streets()
    build_places()
  end

  defp build_places do
    query!("""
    CREATE TABLE #{@schema}.places AS
    SELECT name, district, type,
           ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_Union(geom)), 3)) AS geom
    FROM (
      -- the district is only looked up for the areas that are a place
      SELECT tagged.*,
             (SELECT d.name FROM #{@schema}.districts d
              WHERE ST_Contains(d.geom, ST_PointOnSurface(tagged.geom)) LIMIT 1) AS district
      FROM (
        SELECT trim(m.name) AS name, #{@place_type_sql} AS type, m.geom
        FROM #{@schema}.multipolygons m
        WHERE m.name IS NOT NULL
      ) tagged
      WHERE tagged.type IS NOT NULL
    ) places
    WHERE district IS NOT NULL
    GROUP BY name, district, type
    HAVING type <> 'Water' OR ST_Area(ST_Union(geom)::geography) >= #{@min_water_area}
    """)
  end

  defp build_addresses do
    query!("""
    CREATE TABLE #{@schema}.addresses AS
    WITH raw AS (
      SELECT osm_id AS osm_ref, 0 AS priority, addr_street AS street,
             addr_housenumber AS housenumber, addr_postcode AS postcode, geom
      FROM #{@schema}.points
      WHERE addr_street IS NOT NULL AND addr_housenumber IS NOT NULL
      UNION ALL
      SELECT CASE WHEN osm_way_id IS NOT NULL THEN 'way/' || osm_way_id ELSE 'relation/' || osm_id END,
             1, addr_street, addr_housenumber, addr_postcode, ST_PointOnSurface(geom)
      FROM #{@schema}.multipolygons
      WHERE addr_street IS NOT NULL AND addr_housenumber IS NOT NULL
    ),
    parts AS (
      SELECT raw.*, upper(regexp_replace(n, '\\s+', '', 'g')) AS part
      FROM raw, unnest(regexp_split_to_array(raw.housenumber, '\\s*[;,]\\s*')) AS n
      WHERE trim(n) <> ''
    ),
    -- "41-42" is a range, "108/118" two numbers. Big ranges only keep their ends.
    numbers AS (
      SELECT parts.*, number, count(*) OVER (PARTITION BY parts.osm_ref) AS numbers_on_feature
      FROM parts,
        LATERAL (SELECT regexp_match(parts.part, '^(\\d+)([-/])(\\d+)$') AS m) matched,
        LATERAL unnest(
          CASE
            WHEN matched.m IS NULL THEN ARRAY[parts.part]
            WHEN matched.m[2] = '-' AND matched.m[3]::int - matched.m[1]::int BETWEEN 1 AND 20
              THEN ARRAY(SELECT generate_series(matched.m[1]::int, matched.m[3]::int)::text)
            ELSE ARRAY[matched.m[1], matched.m[3]]
          END
        ) AS number
    ),
    located AS (
      SELECT
        CASE WHEN numbers_on_feature > 1 THEN osm_ref || '#' || number ELSE osm_ref END AS external_id,
        priority, trim(street) AS street, number,
        coalesce(postcode, (SELECT p.postal_code FROM #{@schema}.postcodes p
                            WHERE ST_Contains(p.geom, numbers.geom) LIMIT 1)) AS zip,
        (SELECT d.name FROM #{@schema}.districts d WHERE ST_Contains(d.geom, numbers.geom) LIMIT 1) AS district,
        (SELECT o.name FROM #{@schema}.ortsteile o WHERE ST_Contains(o.geom, numbers.geom) LIMIT 1) AS ortsteil,
        geom
      FROM numbers
    )
    -- The same address is often mapped as a node and as a building, keep one
    SELECT DISTINCT ON (street, district, number) external_id, street, number, zip, district, ortsteil, geom
    FROM located
    WHERE district IS NOT NULL
    ORDER BY street, district, number, priority, external_id
    """)

    query!("CREATE INDEX ON #{@schema}.addresses (street, district)")
  end

  defp build_streets do
    query!(
      """
      CREATE TABLE #{@schema}.street_parts AS
      SELECT l.name, d.name AS district,
             CASE WHEN ST_Within(l.geom, d.geom) THEN l.geom
                  ELSE ST_CollectionExtract(ST_Intersection(l.geom, d.geom), 2) END AS geom
      FROM #{@schema}.lines l
      JOIN #{@schema}.districts d ON ST_Intersects(l.geom, d.geom)
      WHERE l.name IS NOT NULL AND l.highway IS NOT NULL
        AND (l.highway = ANY($1)
             OR l.name IN (SELECT DISTINCT street FROM #{@schema}.addresses))
      """,
      [@street_highways]
    )

    query!("""
    CREATE TABLE #{@schema}.streets AS
    WITH lines AS (
      SELECT name, district, ST_LineMerge(ST_Collect(geom)) AS geom
      FROM #{@schema}.street_parts
      WHERE NOT ST_IsEmpty(geom)
      GROUP BY name, district
    ),
    addresses AS (
      SELECT street AS name, district, count(*) AS street_number_count,
             ST_Collect(geom) AS points,
             mode() WITHIN GROUP (ORDER BY ortsteil) AS ortsteil
      FROM #{@schema}.addresses
      GROUP BY street, district
    ),
    streets AS (
      SELECT coalesce(l.name, a.name) AS name,
             coalesce(l.district, a.district) AS district,
             l.geom AS geometry,
             coalesce(ST_ClosestPoint(l.geom, ST_Centroid(l.geom)),
                      ST_ClosestPoint(a.points, ST_Centroid(a.points))) AS geo_point,
             coalesce(a.street_number_count, 0) AS street_number_count,
             a.ortsteil
      FROM lines l
      FULL OUTER JOIN addresses a ON a.name = l.name AND a.district = l.district
    )
    SELECT s.name, s.district, s.geometry, s.geo_point, s.street_number_count,
           coalesce(s.ortsteil,
                    (SELECT o.name FROM #{@schema}.ortsteile o
                     WHERE ST_Contains(o.geom, s.geo_point) LIMIT 1)) AS ortsteil
    FROM streets s
    """)

    query!("CREATE UNIQUE INDEX ON #{@schema}.streets (name, district)")
  end

  @doc """
  Moves the staging data into the real tables. Runs in one transaction.
  """
  def upsert do
    {:ok, changes} =
      Repo.transaction(
        fn ->
          streets_upserted =
            query!("""
            INSERT INTO geo_streets
              (name, district, city, ortsteil, geometry, geo_point, street_number_count, inserted_at, updated_at)
            SELECT name, district, 'Berlin', ortsteil, geometry, geo_point, street_number_count, now(), now()
            FROM #{@schema}.streets
            ON CONFLICT (name, district) DO UPDATE SET
              geometry = EXCLUDED.geometry,
              geo_point = EXCLUDED.geo_point,
              street_number_count = EXCLUDED.street_number_count,
              ortsteil = EXCLUDED.ortsteil,
              city = EXCLUDED.city,
              updated_at = now()
            WHERE (geo_streets.geometry, geo_streets.geo_point, geo_streets.street_number_count, geo_streets.ortsteil)
              IS DISTINCT FROM (EXCLUDED.geometry, EXCLUDED.geo_point, EXCLUDED.street_number_count, EXCLUDED.ortsteil)
            """).num_rows

          numbers_upserted =
            query!("""
            INSERT INTO geo_street_numbers
              (external_id, geo_street_id, number, zip, ortsteil, geo_point, inserted_at, updated_at)
            SELECT a.external_id, s.id, a.number, a.zip, a.ortsteil, a.geom, now(), now()
            FROM #{@schema}.addresses a
            JOIN geo_streets s ON s.name = a.street AND s.district = a.district
            ON CONFLICT (external_id) DO UPDATE SET
              geo_street_id = EXCLUDED.geo_street_id,
              number = EXCLUDED.number,
              zip = EXCLUDED.zip,
              ortsteil = EXCLUDED.ortsteil,
              geo_point = EXCLUDED.geo_point,
              updated_at = now()
            WHERE (geo_street_numbers.geo_street_id, geo_street_numbers.number, geo_street_numbers.zip,
                   geo_street_numbers.ortsteil, geo_street_numbers.geo_point)
              IS DISTINCT FROM (EXCLUDED.geo_street_id, EXCLUDED.number, EXCLUDED.zip,
                                EXCLUDED.ortsteil, EXCLUDED.geo_point)
            """).num_rows

          numbers_deleted =
            query!("""
            DELETE FROM geo_street_numbers n
            WHERE NOT EXISTS (SELECT 1 FROM #{@schema}.addresses a WHERE a.external_id = n.external_id)
              AND NOT EXISTS (SELECT 1 FROM geo_street_numbers_news_items l WHERE l.geo_street_number_id = n.id)
            """).num_rows

          streets_deleted =
            query!("""
            DELETE FROM geo_streets s
            WHERE NOT EXISTS (SELECT 1 FROM #{@schema}.streets i
                              WHERE i.name = s.name AND i.district IS NOT DISTINCT FROM s.district)
              AND NOT EXISTS (SELECT 1 FROM geo_streets_news_items l WHERE l.geo_street_id = s.id)
              AND NOT EXISTS (SELECT 1 FROM geo_street_numbers n WHERE n.geo_street_id = s.id)
            """).num_rows

          places = upsert_places()
          news_items_updated = update_news_item_geometries()

          %{
            places_upserted: places.upserted,
            places_adopted: places.adopted,
            place_links_moved: places.links_moved,
            places_deleted: places.deleted,
            streets_upserted: streets_upserted,
            streets_deleted: streets_deleted,
            numbers_upserted: numbers_upserted,
            numbers_deleted: numbers_deleted,
            news_items_updated: news_items_updated
          }
        end,
        timeout: :infinity
      )

    changes
  end

  # Places come from OSM because the names in the official green space register
  # are internal ones like "Puschkinallee/ Am Treptower Park AT GA"
  defp upsert_places do
    # The old register had some parks in several parts with the same name. Only one
    # of them (preferably one with news items) gets the new key, the links of the
    # others are moved to it below.
    adopted =
      query!(
        """
        UPDATE geo_places p SET external_id = c.key
        FROM (
          SELECT DISTINCT ON (g.name, g.district, g.type) g.id, #{place_key("i")} AS key
          FROM geo_places g
          JOIN #{@schema}.places i
            ON g.name = i.name AND g.district = i.district AND g.type = i.type
          WHERE g.type = ANY($1)
          ORDER BY g.name, g.district, g.type,
                   EXISTS (SELECT 1 FROM geo_places_news_items l WHERE l.geo_place_id = g.id) DESC,
                   g.id
        ) c
        WHERE p.id = c.id
          AND p.external_id IS DISTINCT FROM c.key
          AND NOT EXISTS (SELECT 1 FROM geo_places e WHERE e.external_id = c.key)
        """,
        [place_types()]
      ).num_rows

    upserted =
      query!("""
      INSERT INTO geo_places (external_id, name, district, city, type, geometry, geo_point, inserted_at, updated_at)
      SELECT #{place_key("places")}, name, district, 'Berlin', type, geom,
             ST_PointOnSurface(geom), now(), now()
      FROM #{@schema}.places
      WHERE NOT ST_IsEmpty(geom)
      ON CONFLICT (external_id) DO UPDATE SET
        name = EXCLUDED.name,
        district = EXCLUDED.district,
        type = EXCLUDED.type,
        geometry = EXCLUDED.geometry,
        geo_point = EXCLUDED.geo_point,
        updated_at = now()
      WHERE (geo_places.name, geo_places.district, geo_places.type, geo_places.geometry, geo_places.geo_point)
        IS DISTINCT FROM (EXCLUDED.name, EXCLUDED.district, EXCLUDED.type, EXCLUDED.geometry, EXCLUDED.geo_point)
      """).num_rows

    # other places with the same name, district and type as an imported one
    duplicates = """
    geo_places p, geo_places k
    WHERE l.geo_place_id = p.id AND p.type = ANY($1) AND k.type = p.type
      AND k.external_id = #{place_key("p")} AND k.id <> p.id
    """

    links_moved =
      query!(
        """
        INSERT INTO geo_places_news_items (news_item_id, geo_place_id)
        SELECT l.news_item_id, k.id FROM geo_places_news_items l, #{duplicates}
        ON CONFLICT DO NOTHING
        """,
        [place_types()]
      ).num_rows

    query!("DELETE FROM geo_places_news_items l USING #{duplicates}", [place_types()])

    deleted =
      query!(
        """
        DELETE FROM geo_places p
        WHERE p.type = ANY($1)
          AND NOT EXISTS (SELECT 1 FROM #{@schema}.places i
                          WHERE p.external_id = #{place_key("i")})
          AND NOT EXISTS (SELECT 1 FROM geo_places_news_items l WHERE l.geo_place_id = p.id)
        """,
        [place_types()]
      ).num_rows

    %{adopted: adopted, upserted: upserted, links_moved: links_moved, deleted: deleted}
  end

  @doc """
  The types of places this import owns, see `@place_types`.
  """
  def place_types, do: Enum.map(@place_types, &elem(&1, 0))

  # 'osm-park:Pankow:Mauerpark' - the prefix of the parks is kept, so their ids
  # and the links to news items survive the import of the other types
  defp place_key(table) do
    "'osm-' || lower(#{table}.type) || ':' || #{table}.district || ':' || #{table}.name"
  end

  @doc """
  Recalculates the cached geometries of all news items from their linked
  streets, street numbers and places.
  """
  def update_news_item_geometries do
    query!("""
    WITH positions AS (
      SELECT l.news_item_id, s.geometry, s.geo_point
      FROM geo_streets_news_items l JOIN geo_streets s ON s.id = l.geo_street_id
      UNION ALL
      SELECT l.news_item_id, NULL, n.geo_point
      FROM geo_street_numbers_news_items l JOIN geo_street_numbers n ON n.id = l.geo_street_number_id
      UNION ALL
      SELECT l.news_item_id, p.geometry, p.geo_point
      FROM geo_places_news_items l JOIN geo_places p ON p.id = l.geo_place_id
    ),
    collected AS (
      SELECT news_item_id,
             ST_ForceCollection(ST_Collect(geometry)) AS geometries,
             ST_Multi(ST_Collect(geo_point)) AS geo_points
      FROM positions
      GROUP BY news_item_id
    )
    UPDATE news_items n
    SET geometries = c.geometries, geo_points = c.geo_points
    FROM collected c
    WHERE c.news_item_id = n.id
      AND (n.geometries, n.geo_points) IS DISTINCT FROM (c.geometries, c.geo_points)
    """).num_rows
  end

  defp counts do
    %{rows: [[streets, numbers, street_links, number_links]]} =
      query!("""
      SELECT (SELECT count(*) FROM geo_streets), (SELECT count(*) FROM geo_street_numbers),
             (SELECT count(*) FROM geo_streets_news_items),
             (SELECT count(*) FROM geo_street_numbers_news_items)
      """)

    %{
      streets: streets,
      street_numbers: numbers,
      street_links: street_links,
      street_number_links: number_links
    }
  end

  defp staging_counts do
    %{rows: [[districts, ortsteile, addresses, streets, places]]} =
      query!("""
      SELECT (SELECT count(DISTINCT name) FROM #{@schema}.districts),
             (SELECT count(DISTINCT name) FROM #{@schema}.ortsteile),
             (SELECT count(*) FROM #{@schema}.addresses),
             (SELECT count(*) FROM #{@schema}.streets),
             (SELECT count(*) FROM #{@schema}.places)
      """)

    %{
      districts: districts,
      ortsteile: ortsteile,
      addresses: addresses,
      streets: streets,
      places: places
    }
  end

  defp query!(sql, params \\ []) do
    Repo.query!(sql, params, timeout: :infinity, log: false)
  end
end
