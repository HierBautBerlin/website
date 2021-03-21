Postgrex.Types.define(
  Hierbautberlin.PostgresTypes,
  [Geo.PostGIS.Extension] ++ Ecto.Adapters.Postgres.extensions(),
  json: Jason
)
