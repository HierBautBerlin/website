defmodule Hierbautberlin.Importer do
  @moduledoc """
  Runs the importers. Every importer runs in its own process with a timeout, so
  a crashing or hanging data source doesn't stop the others.
  """
  require Logger

  alias Hierbautberlin.GeoData.{AnalyzeText, MapFeatures}
  alias Hierbautberlin.Importer

  @timeout :timer.minutes(30)

  def import_daily do
    # Streets and places are imported by a separate task (see GeoImport)
    AnalyzeText.reload_if_changed()

    run_importers([
      {"BerlinBebauungsplaene", &Importer.BerlinBebauungsplaene.import/0},
      {"Infravelo", &Importer.Infravelo.import/0},
      {"MeinBerlin", &Importer.MeinBerlin.import/0},
      {"UVP", &Importer.UVP.import/0},
      {"DafMap", &Importer.DafMap.import/0},
      {"BerlinerAmtsblatt", &Importer.BerlinerAmtsblatt.import_webpage/0}
    ])

    # The map reads from a materialized view. It is also refreshed daily
    # because it contains dates relative to now.
    MapFeatures.refresh()
  end

  def import_hourly do
    run_importers([
      {"BerlinPresse", &Importer.BerlinPresse.import/0},
      {"GruenBerlin", &Importer.GruenBerlin.import/0},
      {"BerlinerAmtsblatt folder", &Importer.BerlinerAmtsblatt.import_folder/0}
    ])

    MapFeatures.refresh()
  end

  @doc """
  Runs the importers one after another and returns a result per importer.
  """
  def run_importers(importers, timeout \\ @timeout) do
    Enum.map(importers, fn {name, fun} ->
      started = System.monotonic_time(:millisecond)
      task = Task.Supervisor.async_nolink(Hierbautberlin.ImporterTaskSupervisor, fun)

      result =
        case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
          {:ok, {:ok, items}} -> {:ok, length(List.flatten(items))}
          {:ok, {:error, error}} -> {:error, error}
          {:ok, other} -> {:error, {:unexpected_result, other}}
          {:exit, reason} -> {:error, {:exit, reason}}
          nil -> {:error, :timeout}
        end

      duration = System.monotonic_time(:millisecond) - started
      log_result(name, result, duration)
      {name, result}
    end)
  end

  defp log_result(name, {:ok, count}, duration) do
    Logger.info("Importer #{name}: #{count} items in #{duration}ms")
  end

  defp log_result(name, {:error, error}, duration) do
    Logger.error("Importer #{name} failed after #{duration}ms: #{inspect(error)}")

    Bugsnag.report(%RuntimeError{message: "Importer #{name} failed: #{inspect(error)}"},
      severity: "error"
    )
  end
end
