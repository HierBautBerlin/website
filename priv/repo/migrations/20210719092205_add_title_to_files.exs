defmodule Hierbautberlin.Repo.Migrations.AddTitleToFiles do
  use Ecto.Migration

  def change do
    alter table("files") do
      add :title, :string
    end
  end
end
