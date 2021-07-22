defmodule Hierbautberlin.Repo.Migrations.AddHiddenFlag do
  use Ecto.Migration

  def change do
    alter table(:news_items) do
      add :hidden, :boolean, default: false
    end

    alter table(:geo_items) do
      add :hidden, :boolean, default: false
    end
  end
end
