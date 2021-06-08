defmodule Hierbautberlin.Repo.Migrations.AddDateUpdatedToGeoItems do
  use Ecto.Migration

  def change do
    alter table(:geo_items) do
      add :date_updated, :timestamptz
    end
  end
end
