defmodule Hierbautberlin.Repo.Migrations.AddInterpolatedAddresses do
  use Ecto.Migration

  def change do
    # House numbers that are not in OSM but were interpolated between two known
    # neighbours (see AddressMatcher). They have no external_id, so the OSM
    # import deletes them again as soon as no news item links them.
    alter table(:geo_street_numbers) do
      add :interpolated, :boolean, default: false, null: false
    end

    create unique_index(:geo_street_numbers, [:geo_street_id, :number],
             where: "interpolated",
             name: :geo_street_numbers_interpolated_index
           )

    # Streets that were mentioned with a house number we could neither find nor
    # interpolate. They stay linked for context, but must not draw their
    # geometry or their point on the map.
    alter table(:news_items) do
      add :context_street_ids, {:array, :bigint}, default: [], null: false
    end
  end
end
