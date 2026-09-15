defmodule Hierbautberlin.Repo.Migrations.AddRelevance do
  use Ecto.Migration

  # See Hierbautberlin.GeoData.Relevance. The values set here are simple
  # defaults: `mix geo.relevance` calculates them for news items, the importers
  # set them for geo items.
  def up do
    for table <- [:geo_items, :news_items] do
      alter table(table) do
        add :importance, :float, null: false, default: 1.0
        add :relevant_from, :utc_datetime
        add :relevant_until, :utc_datetime
        add :relevance_half_life, :integer, null: false, default: 30
      end
    end

    flush()

    # MapFeatures.list_items/3 looks up the few important items separately
    for table <- ~w(geo_items news_items) do
      execute """
      CREATE INDEX #{table}_important_idx ON #{table} (id)
      INCLUDE (relevant_from, relevant_until, relevance_half_life) WHERE importance >= 2
      """
    end

    execute """
    UPDATE geo_items SET
      relevant_from = coalesce(date_start, date_end, date_updated),
      relevant_until = coalesce(date_end, date_start, date_updated),
      relevance_half_life = 180
    """

    execute """
    UPDATE news_items SET
      relevant_from = published_at,
      relevant_until = published_at + interval '14 days'
    """

    # 1 within the relevant period, halves every `half_life` days afterwards.
    # Upcoming items halve every 180 days until they start, items without any
    # date get 0.3.
    execute """
    CREATE FUNCTION relevance_time_factor(
      relevant_from timestamp, relevant_until timestamp, half_life integer
    ) RETURNS double precision LANGUAGE sql STABLE AS $$
      SELECT CASE
        WHEN relevant_from IS NULL AND relevant_until IS NULL THEN 0.3
        WHEN now() AT TIME ZONE 'UTC' < coalesce(relevant_from, relevant_until) THEN
          power(0.5, least(50, extract(epoch FROM coalesce(relevant_from, relevant_until) - now() AT TIME ZONE 'UTC') / 86400.0 / 180))
        WHEN now() AT TIME ZONE 'UTC' > coalesce(relevant_until, relevant_from) THEN
          power(0.5, least(50, extract(epoch FROM now() AT TIME ZONE 'UTC' - coalesce(relevant_until, relevant_from)) / 86400.0 / greatest(half_life, 1)))
        ELSE 1.0
      END
    $$
    """
  end

  def down do
    execute "DROP FUNCTION relevance_time_factor(timestamp, timestamp, integer)"
    execute "DROP INDEX geo_items_important_idx"
    execute "DROP INDEX news_items_important_idx"

    for table <- [:geo_items, :news_items] do
      alter table(table) do
        remove :importance
        remove :relevant_from
        remove :relevant_until
        remove :relevance_half_life
      end
    end
  end
end
