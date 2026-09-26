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
  Runs the address matching again for existing news items, the release version
  of `mix geo.reanalyze` (see `Hierbautberlin.GeoData.Reanalyze`).

      bin/hierbautberlin eval 'Hierbautberlin.Release.reanalyze("BERLIN_PRESSE")'
      bin/hierbautberlin eval 'Hierbautberlin.Release.reanalyze("BERLIN_PRESSE", since: "2026-09-01")'
      bin/hierbautberlin eval 'Hierbautberlin.Release.reanalyze("BERLIN_PRESSE", stored_only: true)'

  Nothing is changed unless `apply: true` is given. Press releases without a
  stored text are fetched again, so a full run takes a while, unless
  `stored_only: true` skips them.
  """
  def reanalyze(source, opts \\ []) do
    start_app()

    since =
      case Keyword.get(opts, :since) do
        nil -> nil
        date -> DateTime.new!(Date.from_iso8601!(date), ~T[00:00:00], "Etc/UTC")
      end

    apply? = Keyword.get(opts, :apply, false)

    ensure_geo_index()

    stats =
      Hierbautberlin.GeoData.Reanalyze.run(
        source: source,
        since: since,
        dry_run: !apply?,
        stored_only: Keyword.get(opts, :stored_only, false)
      )

    IO.puts(inspect(stats))

    if apply? do
      Hierbautberlin.GeoData.MapFeatures.refresh()
      IO.puts("Refreshed the map features")
    else
      IO.puts("Dry run, nothing was changed. Pass apply: true to store the changes.")
    end

    stats
  end

  @doc """
  Imports the whole archive of Grün Berlin press releases (about 30 list pages,
  back to 2018). The hourly import only reads the newest pages, see
  `Hierbautberlin.Importer.GruenBerlin`.

      bin/hierbautberlin eval 'Hierbautberlin.Release.import_gruen_berlin_archive()'
  """
  def import_gruen_berlin_archive(pages \\ 40) do
    start_app()
    ensure_geo_index()

    {:ok, items} =
      Hierbautberlin.Importer.GruenBerlin.import(Hierbautberlin.HTTPClient, pages: pages)

    located = Enum.count(items, &(&1.geo_points || &1.geometries))
    IO.puts("Imported #{length(items)} press releases, #{located} of them with a location")
    Hierbautberlin.GeoData.MapFeatures.refresh()
    IO.puts("Refreshed the map features")
  end

  @doc """
  Imports the press releases of the building and transport departments and the
  Landesdenkmalamt since 2022, which the hourly import missed while it used the
  old names of the departments. Takes about half an hour, a second run only
  imports what is still missing. See `Hierbautberlin.Importer.BerlinPresse`.

      bin/hierbautberlin eval 'Hierbautberlin.Release.import_berlin_presse_archive()'
  """
  def import_berlin_presse_archive(max_pages \\ 200) do
    start_app()
    ensure_geo_index()

    {:ok, items} =
      Hierbautberlin.Importer.BerlinPresse.import_archive(
        Hierbautberlin.HTTPClient.Slow,
        max_pages
      )

    located = Enum.count(items, &(&1.geo_points || &1.geometries))
    IO.puts("Imported #{length(items)} press releases, #{located} of them with a location")
    Hierbautberlin.GeoData.MapFeatures.refresh()
    IO.puts("Refreshed the map features")
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

  # Loads the streets and places the address matching needs. `bin/hierbautberlin
  # eval` starts the app with the importer children, so `AnalyzeText` owns the
  # index there. Run from mix the app is already started without those children:
  # then the index is loaded here, otherwise it stays empty and nothing is found.
  defp ensure_geo_index do
    if Process.whereis(Hierbautberlin.GeoData.AnalyzeText) do
      Hierbautberlin.GeoData.AnalyzeText.reload()
    else
      Hierbautberlin.GeoData.AddressMatcher.load_index()
    end
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
