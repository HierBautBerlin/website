defmodule Hierbautberlin.Repo.Migrations.AddNewsItems do
  use Ecto.Migration

  def change do
    create table(:news_items) do
      add :external_id, :string
      add :title, :string
      add :content, :text
      add :link, :text
      add :published_at, :naive_datetime
      add :source_id, references(:sources)

      timestamps(type: :timestamptz)
    end

    create unique_index(:news_items, [:external_id])

    create table(:geo_streets_news_items, primary_key: false) do
      add :news_item_id, references(:news_items)
      add :geo_street_id, references(:geo_streets)
    end

    create index(:geo_streets_news_items, [:news_item_id])
    create index(:geo_streets_news_items, [:geo_street_id])

    create table(:geo_street_numbers_news_items, primary_key: false) do
      add :news_item_id, references(:news_items)
      add :geo_street_number_id, references(:geo_street_numbers)
    end

    create index(:geo_street_numbers_news_items, [:news_item_id])
    create index(:geo_street_numbers_news_items, [:geo_street_number_id])

    create table(:geo_places_news_items, primary_key: false) do
      add :news_item_id, references(:news_items)
      add :geo_place_id, references(:geo_places)
    end

    create index(:geo_places_news_items, [:news_item_id])
    create index(:geo_places_news_items, [:geo_place_id])
  end
end
