defmodule Hierbautberlin.Repo.Migrations.AddTextSearchIndexes do
  use Ecto.Migration

  # Trigram indexes for the text search of the map list (ILIKE '%…%'), see
  # MapFeatures.list_items/3. The expressions must match the query.
  def up do
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"

    execute """
    CREATE INDEX geo_items_text_trgm_idx ON geo_items USING gin (
      (coalesce(title, '') || ' ' || coalesce(subtitle, '') || ' ' || coalesce(description, '')) gin_trgm_ops
    )
    """

    execute """
    CREATE INDEX news_items_text_trgm_idx ON news_items USING gin (
      (coalesce(title, '') || ' ' || coalesce(content, '')) gin_trgm_ops
    )
    """
  end

  def down do
    execute "DROP INDEX geo_items_text_trgm_idx"
    execute "DROP INDEX news_items_text_trgm_idx"
  end
end
