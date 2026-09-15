defmodule Hierbautberlin.Release do
  @app :hierbautberlin

  def init_data do
    start_app()
    Hierbautberlin.Importer.import_daily()
    Hierbautberlin.Importer.import_hourly()
  end

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Imports streets and street numbers from an OSM extract and places from
  gdi.berlin.de, see `Hierbautberlin.GeoImport`.

      bin/hierbautberlin eval 'Hierbautberlin.Release.import_geo_data("/tmp/berlin-latest.osm.pbf")'

  The running app picks up the changes with the next daily import.
  """
  def import_geo_data(osm_file) do
    load_app()

    Ecto.Migrator.with_repo(Hierbautberlin.Repo, fn _repo ->
      {:ok, _} = Application.ensure_all_started(:req)
      IO.puts("Importing streets from #{osm_file}..")
      IO.puts(inspect(Hierbautberlin.GeoImport.import_osm(osm_file)))
      IO.puts("Importing places..")
      IO.puts(inspect(Hierbautberlin.GeoImport.import_places()))
    end)
  end

  def refresh_news_items do
    start_app()
    Hierbautberlin.GeoData.NewsItem.update_all_geometries()
  end

  @doc """
  Calculates the relevance of all news items again, see
  `Hierbautberlin.GeoData.Relevance`.
  """
  def update_relevance do
    load_app()

    Ecto.Migrator.with_repo(Hierbautberlin.Repo, fn _repo ->
      count = Hierbautberlin.GeoData.Relevance.update_news_items()
      IO.puts("Updated #{count} news items")
    end)
  end

  @doc """
  Repairs the Amtsblatt PDF links of April to June 2023, see
  `Hierbautberlin.Importer.AmtsblattFileNames`. Needs the file storage.
  """
  def repair_amtsblatt_file_names do
    load_app()

    Ecto.Migrator.with_repo(Hierbautberlin.Repo, fn _repo ->
      IO.puts(inspect(Hierbautberlin.Importer.AmtsblattFileNames.run()))
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
    Application.put_env(@app, :data_importer, true)
    Application.ensure_all_started(@app)
  end
end
