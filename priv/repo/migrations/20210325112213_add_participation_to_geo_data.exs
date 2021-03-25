defmodule Hierbautberlin.Repo.Migrations.AddParticipationToGeoData do
  use Ecto.Migration

  def change do
    alter table(:geo_items) do
      add :participation_open, :boolean, default: false
    end
  end
end
