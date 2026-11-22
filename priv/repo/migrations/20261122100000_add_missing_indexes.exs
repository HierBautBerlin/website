defmodule Hierbautberlin.Repo.Migrations.AddMissingIndexes do
  use Ecto.Migration

  # CONCURRENTLY doesn't lock the tables while the indexes are built, but can't
  # run inside a transaction
  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # The "important" part of MapFeatures.list_items/3 (fresh press releases)
    # and the newest Amtsblatt issue. Without it every list query reads the
    # whole news_items table.
    create_if_not_exists index(:news_items, [:published_at], concurrently: true)

    # RSS feeds and subscription mails: items of the last weeks around a place
    create_if_not_exists index(:news_items, [:inserted_at], concurrently: true)
    create_if_not_exists index(:geo_items, [:inserted_at], concurrently: true)

    # max(updated_at) for MapFeatures.version/0
    create_if_not_exists index(:news_items, [:updated_at], concurrently: true)
    create_if_not_exists index(:geo_items, [:updated_at], concurrently: true)

    # PDFs are looked up by name (view_pdf) and the name decides where the file
    # is stored, so it has to be unique. A failed concurrent build would leave
    # an invalid index behind, so duplicates are reported first.
    %{rows: duplicates} =
      repo().query!("SELECT name FROM files GROUP BY name HAVING count(*) > 1")

    if duplicates != [] do
      raise "files.name is not unique, remove the duplicates first: #{inspect(duplicates)}"
    end

    create_if_not_exists unique_index(:files, [:name], concurrently: true)
  end

  def down do
    drop_if_exists index(:files, [:name], concurrently: true)
    drop_if_exists index(:geo_items, [:updated_at], concurrently: true)
    drop_if_exists index(:news_items, [:updated_at], concurrently: true)
    drop_if_exists index(:geo_items, [:inserted_at], concurrently: true)
    drop_if_exists index(:news_items, [:inserted_at], concurrently: true)
    drop_if_exists index(:news_items, [:published_at], concurrently: true)
  end
end
