defmodule Hierbautberlin.Repo.Migrations.RenameLinkToUrl do
  use Ecto.Migration

  def change do
    rename table("news_items"), :link, to: :url
  end
end
