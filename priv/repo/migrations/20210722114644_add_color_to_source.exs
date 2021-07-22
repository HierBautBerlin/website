defmodule Hierbautberlin.Repo.Migrations.AddColorToSource do
  use Ecto.Migration

  def change do
    alter table(:sources) do
      add :color, :string
    end
  end
end
