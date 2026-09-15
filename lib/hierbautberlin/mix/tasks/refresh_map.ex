defmodule Mix.Tasks.RefreshMap do
  use Mix.Task

  @shortdoc "Refreshes the map_features materialized view"
  def run(_) do
    Ecto.Migrator.with_repo(Hierbautberlin.Repo, fn _repo ->
      Hierbautberlin.GeoData.MapFeatures.refresh()
    end)
  end
end
