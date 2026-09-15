defmodule Hierbautberlin.Repo.Migrations.CreateMapFeatures do
  use Ecto.Migration

  # One row per drawable feature on the map. Geo items contribute their point,
  # the line and polygon parts of their geometry and a center point for
  # geometry-only items. News items contribute the positions of the streets,
  # street numbers and places they are linked to.
  #
  # News item rows use DISTINCT, so duplicate rows in the link tables can't break
  # the unique index.
  #
  # The view is refreshed by `Hierbautberlin.GeoData.MapFeatures.refresh/0`
  # after imports.
  @view_sql """
  CREATE MATERIALIZED VIEW map_features AS
  WITH geo_items_visible AS (
    SELECT
      gi.*,
      (
        SELECT d FROM unnest(ARRAY[gi.date_start, gi.date_end, gi.date_updated]) AS d
        WHERE d IS NOT NULL
        ORDER BY abs(extract(epoch FROM d - now()))
        LIMIT 1
      ) AS newest_date
    FROM geo_items gi
    WHERE gi.hidden = false
  ),
  news_items_visible AS (
    SELECT * FROM news_items WHERE hidden = false
  )
  SELECT 'geo_item'::text AS item_type, gi.id AS item_id, 'geo_item'::text AS position_type,
         gi.id AS position_id, 'circle'::text AS draw, gi.source_id, gi.title, gi.newest_date,
         gi.participation_open, gi.geo_point AS geom
  FROM geo_items_visible gi
  WHERE gi.geo_point IS NOT NULL

  UNION ALL

  SELECT 'geo_item', gi.id, 'geo_item', gi.id, 'center', gi.source_id, gi.title, gi.newest_date,
         gi.participation_open, ST_Centroid(gi.geometry)
  FROM geo_items_visible gi
  WHERE gi.geo_point IS NULL AND gi.geometry IS NOT NULL

  UNION ALL

  SELECT 'geo_item', gi.id, 'geo_item', gi.id, 'line', gi.source_id, gi.title, gi.newest_date,
         gi.participation_open, ST_CollectionExtract(gi.geometry, 2)
  FROM geo_items_visible gi
  WHERE gi.geometry IS NOT NULL AND NOT ST_IsEmpty(ST_CollectionExtract(gi.geometry, 2))

  UNION ALL

  SELECT 'geo_item', gi.id, 'geo_item', gi.id, 'polygon', gi.source_id, gi.title, gi.newest_date,
         gi.participation_open, ST_CollectionExtract(gi.geometry, 3)
  FROM geo_items_visible gi
  WHERE gi.geometry IS NOT NULL AND NOT ST_IsEmpty(ST_CollectionExtract(gi.geometry, 3))

  UNION ALL

  SELECT DISTINCT 'news_item', n.id, 'geo_street', s.id, 'circle', n.source_id, n.title, n.published_at,
         false, s.geo_point
  FROM news_items_visible n
  JOIN geo_streets_news_items l ON l.news_item_id = n.id
  JOIN geo_streets s ON s.id = l.geo_street_id
  WHERE s.geo_point IS NOT NULL

  UNION ALL

  SELECT DISTINCT 'news_item', n.id, 'geo_street_number', sn.id, 'circle', n.source_id, n.title,
         n.published_at, false, sn.geo_point
  FROM news_items_visible n
  JOIN geo_street_numbers_news_items l ON l.news_item_id = n.id
  JOIN geo_street_numbers sn ON sn.id = l.geo_street_number_id
  WHERE sn.geo_point IS NOT NULL

  UNION ALL

  SELECT DISTINCT 'news_item', n.id, 'geo_place', p.id, 'circle', n.source_id, n.title, n.published_at,
         false, p.geo_point
  FROM news_items_visible n
  JOIN geo_places_news_items l ON l.news_item_id = n.id
  JOIN geo_places p ON p.id = l.geo_place_id
  WHERE p.geo_point IS NOT NULL
  """

  def up do
    # Spatial indexes that were missing so far
    execute "CREATE INDEX IF NOT EXISTS news_items_geometries_idx ON news_items USING GIST (geometries)"

    execute "CREATE INDEX IF NOT EXISTS news_items_geo_points_idx ON news_items USING GIST (geo_points)"

    execute "CREATE INDEX IF NOT EXISTS geo_streets_geometry_idx ON geo_streets USING GIST (geometry)"

    execute "CREATE INDEX IF NOT EXISTS geo_streets_geo_point_idx ON geo_streets USING GIST (geo_point)"

    execute "CREATE INDEX IF NOT EXISTS geo_places_geometry_idx ON geo_places USING GIST (geometry)"

    execute "CREATE INDEX IF NOT EXISTS geo_places_geo_point_idx ON geo_places USING GIST (geo_point)"

    execute "CREATE INDEX IF NOT EXISTS geo_street_numbers_geo_point_idx ON geo_street_numbers USING GIST (geo_point)"

    execute @view_sql

    execute """
    CREATE UNIQUE INDEX map_features_unique_idx
    ON map_features (item_type, item_id, position_type, position_id, draw)
    """

    execute "CREATE INDEX map_features_geom_idx ON map_features USING GIST (geom)"
    execute "CREATE INDEX map_features_item_idx ON map_features (item_type, item_id)"
  end

  def down do
    execute "DROP MATERIALIZED VIEW map_features"

    for index <- ~w(news_items_geometries_idx news_items_geo_points_idx geo_streets_geometry_idx
                    geo_streets_geo_point_idx geo_places_geometry_idx geo_places_geo_point_idx
                    geo_street_numbers_geo_point_idx) do
      execute "DROP INDEX IF EXISTS #{index}"
    end
  end
end
