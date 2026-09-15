defmodule Hierbautberlin.Repo.Migrations.AddFullTextToNewsItems do
  use Ecto.Migration

  def change do
    alter table(:news_items) do
      add :full_text, :text
      add :districts, {:array, :string}, default: []
    end
  end
end
