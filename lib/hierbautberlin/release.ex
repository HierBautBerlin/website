defmodule Hierbautberlin.Release do
  @app :hierbautberlin

  def init_data do
    start_app()
  end

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def import_all do
    IO.puts("Importing streets..")
    Mix.Tasks.ImportStreets.run(nil)
    IO.puts("Importing parks..")
    Mix.Tasks.ImportParks.run(nil)
  end

  def refresh_news_items do
    Ecto.Migrator.with_repo(Hierbautberlin.Repo, fn _repo ->
      Hierbautberlin.GeoData.NewsItem.update_all_geometries()
    end)
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end

  defp start_app do
    load_app()
    Application.put_env(@app, :minimal, true)
    Application.ensure_all_started(@app)
  end
end
