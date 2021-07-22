defmodule Hierbautberlin.Repo.Migrations.AddStreetNumberCount do
  use Ecto.Migration

  def change do
    alter table(:geo_streets) do
      add :street_number_count, :integer, default: 0
    end

    execute(
      """
      UPDATE geo_streets
      SET street_number_count = sub_q.count_val
      FROM (select geo_street_id, count(id) as count_val from geo_street_numbers group by geo_street_id) AS sub_q
      WHERE sub_q.geo_street_id = geo_streets.id;
      """,
      ""
    )
  end
end
