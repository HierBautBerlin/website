defmodule Hierbautberlin.Repo.Migrations.AddSubscriptions do
  use Ecto.Migration

  def change do
    create table(:subscriptions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :radius, :int, default: "2000"
      timestamps()
    end

    create index(:subscriptions, [:user_id])
    execute("SELECT AddGeometryColumn('subscriptions', 'point', 4326, 'POINT', 2);")
  end
end
