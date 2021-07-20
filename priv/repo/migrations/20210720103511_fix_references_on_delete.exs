defmodule Hierbautberlin.Repo.Migrations.FixReferencesOnDelete do
  use Ecto.Migration

  def change do
    alter table(:geo_places_news_items) do
      modify :news_item_id, references(:news_items, on_delete: :delete_all),
        from: references(:news_items, on_delete: :nothing)

      modify :geo_place_id, references(:geo_places, on_delete: :delete_all),
        from: references(:geo_places, on_delete: :nothing)
    end

    alter table(:geo_street_numbers_news_items) do
      modify :news_item_id, references(:news_items, on_delete: :delete_all),
        from: references(:news_items, on_delete: :nothing)

      modify :geo_street_number_id, references(:geo_street_numbers, on_delete: :delete_all),
        from: references(:geo_street_numbers, on_delete: :nothing)
    end

    alter table(:geo_streets_news_items) do
      modify :news_item_id, references(:news_items, on_delete: :delete_all),
        from: references(:news_items, on_delete: :nothing)

      modify :geo_street_id, references(:geo_streets, on_delete: :delete_all),
        from: references(:geo_streets, on_delete: :nothing)
    end
  end
end
