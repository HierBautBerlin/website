defmodule Hierbautberlin.GeoData.AnalyzeText do
  @moduledoc """
  Finds streets, street numbers and places in texts.

  The matching itself is done by `Hierbautberlin.GeoData.AddressMatcher` in the
  calling process. This GenServer owns the index: it loads it on start, reloads
  it when streets or places changed and supports adding single streets and
  places (used by tests).
  """
  use GenServer
  require Logger

  import Ecto.Query, warn: false

  alias Hierbautberlin.GeoData
  alias Hierbautberlin.GeoData.AddressMatcher
  alias Hierbautberlin.Repo

  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, :ok, options)
  end

  @impl true
  def init(:ok) do
    Logger.debug("Booting street analyzer")
    {streets, places} = load_geo_objects()
    AddressMatcher.put_index(AddressMatcher.build_index(streets, places))
    Logger.debug("... with #{length(streets)} Streets and #{length(places)} Places")

    {:ok, %{streets: streets, places: places, fingerprint: geo_objects_fingerprint()}}
  end

  defp load_geo_objects do
    streets = AddressMatcher.load_streets()

    places =
      Repo.all(
        from p in GeoData.GeoPlace,
          select: %{id: p.id, name: p.name, district: p.district, type: p.type}
      )

    {streets, places}
  end

  @doc """
  A value that changes when streets or places were imported.
  """
  def geo_objects_fingerprint do
    %{rows: [row]} =
      Repo.query!("""
      SELECT (SELECT count(*) FROM geo_streets), (SELECT max(updated_at) FROM geo_streets),
             (SELECT count(*) FROM geo_places), (SELECT max(updated_at) FROM geo_places)
      """)

    row
  end

  @impl true
  def handle_call(:reload, _from, _state) do
    fingerprint = geo_objects_fingerprint()
    {:reply, :ok, rebuild(load_geo_objects(), fingerprint)}
  end

  def handle_call(:reload_if_changed, _from, state) do
    fingerprint = geo_objects_fingerprint()

    if state.fingerprint == fingerprint do
      {:reply, :unchanged, state}
    else
      {:reply, :reloaded, rebuild(load_geo_objects(), fingerprint)}
    end
  end

  def handle_call({:reset_index}, _from, _state) do
    {:reply, :ok, rebuild({[], []})}
  end

  def handle_call({:add_streets, streets}, _from, state) do
    streets = Enum.map(streets, &to_street_map/1)
    {:reply, :ok, rebuild({state.streets ++ streets, state.places})}
  end

  def handle_call({:add_places, places}, _from, state) do
    places = Enum.map(places, &Map.take(&1, [:id, :name, :district, :type]))
    {:reply, :ok, rebuild({state.streets, state.places ++ places})}
  end

  @impl true
  def handle_info(message, state) do
    Bugsnag.report(%RuntimeError{message: "unknown message in analyze_text: #{inspect(message)}"},
      severity: "warning"
    )

    {:noreply, state}
  end

  defp rebuild({streets, places}, fingerprint \\ nil) do
    AddressMatcher.put_index(AddressMatcher.build_index(streets, places))
    %{streets: streets, places: places, fingerprint: fingerprint}
  end

  defp to_street_map(street) do
    number_count =
      case street do
        %{street_numbers: numbers} when is_list(numbers) -> length(numbers)
        _ -> street.street_number_count || 0
      end

    %{
      id: street.id,
      name: street.name,
      district: street.district,
      ortsteil: Map.get(street, :ortsteil),
      number_count: number_count
    }
  end

  def add_streets(manager \\ __MODULE__, streets) do
    GenServer.call(manager, {:add_streets, streets})
  end

  def add_places(manager \\ __MODULE__, places) do
    GenServer.call(manager, {:add_places, places})
  end

  @doc """
  Analyzes the text and returns the found streets, street numbers and places.

  Options:
    * `:districts` - the districts the text is about (if known)
  """
  def analyze_text(_manager \\ __MODULE__, text, options) do
    result = AddressMatcher.analyze(text, Map.new(options))

    %{
      streets: GeoData.get_geo_streets(result.streets),
      street_numbers: GeoData.get_geo_street_numbers(result.street_numbers),
      context_streets: GeoData.get_geo_streets(result.context_streets),
      # not stored yet, see GeoData.store_interpolated_numbers/1
      interpolated: result.interpolated,
      places: GeoData.get_geo_places(result.places)
    }
  rescue
    error ->
      Bugsnag.report(error)
      Logger.error("analyze_text failed: #{Exception.format(:error, error, __STACKTRACE__)}")
      %{streets: [], street_numbers: [], context_streets: [], interpolated: [], places: []}
  end

  @doc """
  Reloads all streets and places from the database.
  """
  def reload(manager \\ __MODULE__) do
    GenServer.call(manager, :reload, 300_000)
  end

  @doc """
  Reloads streets and places if they changed since the last reload.
  """
  def reload_if_changed(manager \\ __MODULE__) do
    GenServer.call(manager, :reload_if_changed, 300_000)
  end

  def reset_index(manager \\ __MODULE__) do
    GenServer.call(manager, {:reset_index})
  end
end
