defmodule Hierbautberlin.Repo.Migrations.AddAddionalFieldsToGeoItem do
  use Ecto.Migration

  def change do
    alter table(:geo_items) do
      modify :title, :text
      add :additional_link, :text
      add :additional_link_name, :string
    end
  end
end
