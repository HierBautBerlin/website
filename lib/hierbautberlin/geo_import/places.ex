defmodule Hierbautberlin.GeoImport.Places do
  @moduledoc """
  Imports places (LOR planning areas, schools) from the WFS services of
  the Berlin geodata infrastructure (https://gdi.berlin.de).

  Places are upserted by `external_id`. Places that were imported by older
  importers with different external ids are matched by type, name and district,
  so their ids (and links to news items) are kept. Places of the imported types
  that no longer exist are deleted unless a news item links to them.
  """

  require Logger

  alias Hierbautberlin.Repo

  @wfs_base "https://gdi.berlin.de/services/wfs"

  # Parks are imported from OpenStreetMap, see Hierbautberlin.GeoImport.OSM
  @sources %{
    "LOR" => {"lor_2021", "lor_2021:a_lor_plr_2021"},
    "School" => {"schulen", "schulen:schulen"}
  }

  def types, do: Map.keys(@sources)

  @doc """
  Imports the given place types. `fetch` can be replaced in tests, it receives
  the service and the layer name and returns a decoded GeoJSON map.
  """
  def import(types \\ types(), fetch \\ &fetch_wfs/2) do
    Map.new(types, fn type ->
      {service, layer} = Map.fetch!(@sources, type)
      features = fetch.(service, layer)["features"] || []
      places = to_places(type, features)
      {type, upsert(type, places)}
    end)
  end

  def fetch_wfs(service, layer) do
    Req.get!("#{@wfs_base}/#{service}",
      params: [
        SERVICE: "WFS",
        VERSION: "2.0.0",
        REQUEST: "GetFeature",
        TYPENAMES: layer,
        OUTPUTFORMAT: "application/json",
        SRSNAME: "EPSG:4326"
      ],
      receive_timeout: 300_000,
      decode_body: false
    ).body
    |> Jason.decode!()
  end

  @doc false
  def to_places("LOR", features) do
    Enum.map(features, fn feature ->
      properties = feature["properties"]

      %{
        external_id: "lor:#{properties["plr_id"]}",
        name: properties["plr_name"],
        district: properties["bez"] |> to_string() |> String.replace(~r/^\d+\s*-\s*/, ""),
        geometry: feature["geometry"]
      }
    end)
  end

  def to_places("School", features) do
    Enum.map(features, fn feature ->
      properties = feature["properties"]

      %{
        external_id: properties["bsn"],
        name: String.trim(properties["schulname"]),
        district: properties["bezirk"],
        geometry: feature["geometry"]
      }
    end)
  end

  defp upsert(type, places) do
    {:ok, stats} =
      Repo.transaction(
        fn ->
          Repo.query!("DROP TABLE IF EXISTS import_places")

          Repo.query!(
            "CREATE TEMP TABLE import_places (external_id text, name text, district text, geometry text) ON COMMIT DROP"
          )

          insert_import_places(places)

          # Older imports used other external ids, take over those places
          adopted =
            Repo.query!(
              """
              UPDATE geo_places p SET external_id = i.external_id
              FROM import_places i
              WHERE p.type = $1::text AND p.name = i.name AND p.district IS NOT DISTINCT FROM i.district
                AND p.external_id <> i.external_id
                AND NOT EXISTS (SELECT 1 FROM geo_places e WHERE e.external_id = i.external_id)
              """,
              [type]
            ).num_rows

          upserted =
            Repo.query!(
              """
              INSERT INTO geo_places (external_id, name, district, city, type, geometry, geo_point, inserted_at, updated_at)
              SELECT DISTINCT ON (external_id)
                external_id, name, district, 'Berlin', $1::text,
                -- schools are points, the geometry column is only used for areas
                CASE WHEN $1::text = 'School' THEN NULL ELSE g.geometry END,
                CASE WHEN GeometryType(g.geometry) = 'POINT' THEN g.geometry ELSE ST_PointOnSurface(g.geometry) END,
                now(), now()
              FROM import_places,
                LATERAL (SELECT ST_GeomFromGeoJSON(import_places.geometry) AS raw) r,
                LATERAL (
                  SELECT ST_SetSRID(
                    CASE WHEN GeometryType(r.raw) = 'POINT' THEN r.raw
                         ELSE ST_Multi(ST_CollectionExtract(ST_MakeValid(r.raw), 3)) END,
                    4326
                  ) AS geometry
                ) g
              ORDER BY external_id
              ON CONFLICT (external_id) DO UPDATE SET
                name = EXCLUDED.name,
                district = EXCLUDED.district,
                type = EXCLUDED.type,
                geometry = EXCLUDED.geometry,
                geo_point = EXCLUDED.geo_point,
                updated_at = now()
              WHERE (geo_places.name, geo_places.district, geo_places.type, geo_places.geo_point, geo_places.geometry)
                IS DISTINCT FROM (EXCLUDED.name, EXCLUDED.district, EXCLUDED.type, EXCLUDED.geo_point, EXCLUDED.geometry)
              """,
              [type]
            ).num_rows

          deleted =
            Repo.query!(
              """
              DELETE FROM geo_places p
              WHERE p.type = $1::text
                AND NOT EXISTS (SELECT 1 FROM import_places i WHERE i.external_id = p.external_id)
                AND NOT EXISTS (SELECT 1 FROM geo_places_news_items l WHERE l.geo_place_id = p.id)
              """,
              [type]
            ).num_rows

          %{imported: length(places), adopted: adopted, upserted: upserted, deleted: deleted}
        end,
        timeout: :infinity
      )

    Logger.info("Imported places #{type}: #{inspect(stats)}")
    stats
  end

  defp insert_import_places(places) do
    places
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      {placeholders, params} =
        chunk
        |> Enum.with_index()
        |> Enum.map_reduce([], fn {place, index}, params ->
          base = index * 4

          {"($#{base + 1}, $#{base + 2}, $#{base + 3}, $#{base + 4})",
           params ++
             [place.external_id, place.name, place.district, Jason.encode!(place.geometry)]}
        end)

      Repo.query!("INSERT INTO import_places VALUES #{Enum.join(placeholders, ", ")}", params)
    end)
  end
end
