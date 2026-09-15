defmodule Hierbautberlin.Repo.Migrations.AddStableKeysToGeoObjects do
  use Ecto.Migration

  # The new OSM import upserts streets by (name, district) and street numbers by
  # external_id, so existing ids (and the links to news items) survive re-imports.
  #
  # Older imports could create duplicates. They are merged into the row with the
  # lowest id before the unique indexes are created; links are moved over.
  def up do
    # Streets: merge duplicates of (name, district)
    execute """
    CREATE TEMP TABLE street_duplicates AS
    SELECT id, min(id) OVER (PARTITION BY name, district) AS keep_id
    FROM geo_streets
    """

    execute "DELETE FROM street_duplicates WHERE id = keep_id"

    execute """
    UPDATE geo_street_numbers n SET geo_street_id = d.keep_id
    FROM street_duplicates d WHERE n.geo_street_id = d.id
    """

    execute """
    UPDATE geo_streets_news_items l SET geo_street_id = d.keep_id
    FROM street_duplicates d WHERE l.geo_street_id = d.id
    """

    execute "DELETE FROM geo_streets s USING street_duplicates d WHERE s.id = d.id"
    execute "DROP TABLE street_duplicates"

    # Street numbers: merge duplicates of external_id
    execute """
    CREATE TEMP TABLE number_duplicates AS
    SELECT id, min(id) OVER (PARTITION BY external_id) AS keep_id
    FROM geo_street_numbers
    WHERE external_id IS NOT NULL
    """

    execute "DELETE FROM number_duplicates WHERE id = keep_id"

    execute """
    UPDATE geo_street_numbers_news_items l SET geo_street_number_id = d.keep_id
    FROM number_duplicates d WHERE l.geo_street_number_id = d.id
    """

    execute "DELETE FROM geo_street_numbers n USING number_duplicates d WHERE n.id = d.id"
    execute "DROP TABLE number_duplicates"

    # Remove duplicate links (can be created by the merges above)
    for {table, column} <- [
          {"geo_streets_news_items", "geo_street_id"},
          {"geo_street_numbers_news_items", "geo_street_number_id"},
          {"geo_places_news_items", "geo_place_id"}
        ] do
      execute """
      DELETE FROM #{table} a USING #{table} b
      WHERE a.ctid > b.ctid AND a.news_item_id = b.news_item_id AND a.#{column} = b.#{column}
      """

      create unique_index(table, [:news_item_id, String.to_atom(column)])
    end

    drop index(:geo_street_numbers, [:external_id])
    create unique_index(:geo_street_numbers, [:external_id])
    create unique_index(:geo_streets, [:name, :district])
    create index(:geo_street_numbers, [:geo_street_id])

    alter table(:geo_streets) do
      add :ortsteil, :string
    end

    alter table(:geo_street_numbers) do
      add :ortsteil, :string
    end
  end

  def down do
    alter table(:geo_street_numbers) do
      remove :ortsteil
    end

    alter table(:geo_streets) do
      remove :ortsteil
    end

    drop index(:geo_street_numbers, [:geo_street_id])
    drop unique_index(:geo_streets, [:name, :district])
    drop unique_index(:geo_street_numbers, [:external_id])
    create index(:geo_street_numbers, [:external_id])

    drop unique_index(:geo_streets_news_items, [:news_item_id, :geo_street_id])
    drop unique_index(:geo_street_numbers_news_items, [:news_item_id, :geo_street_number_id])
    drop unique_index(:geo_places_news_items, [:news_item_id, :geo_place_id])
  end
end
