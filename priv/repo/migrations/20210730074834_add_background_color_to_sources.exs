defmodule Hierbautberlin.Repo.Migrations.AddBackgroundColorToSources do
  use Ecto.Migration

  def change do
    alter table(:sources) do
      add :background_color, :string
    end
  end
end
