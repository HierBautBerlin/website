defmodule Hierbautberlin.Importer.Check do
  @moduledoc """
  Runs importers against the live data sources without keeping any data.

  Every importer runs inside a database transaction that is rolled back. All
  HTTP requests are recorded (status, size, duration) and the response bodies
  are written to `tmp/importer_check/<importer>/`, which makes it easy to
  refresh test fixtures.
  """

  alias Hierbautberlin.Importer
  alias Hierbautberlin.Repo

  @importers %{
    "berlin_bebauungsplaene" => {Importer.BerlinBebauungsplaene, :import, []},
    "infravelo" => {Importer.Infravelo, :import, []},
    "mein_berlin" => {Importer.MeinBerlin, :import, []},
    "uvp" => {Importer.UVP, :import, []},
    "daf_map" => {Importer.DafMap, :import, []},
    "berliner_amtsblatt" => {Importer.BerlinerAmtsblatt, :import_webpage, [:downloader]},
    "berlin_presse" => {Importer.BerlinPresse, :import, []},
    # the article pages are only fetched for releases that are not stored yet,
    # for the check every release of the first pages is fetched
    "gruen_berlin" => {Importer.GruenBerlin, :import, [[skip_imported: false]]}
  }

  def importer_names, do: @importers |> Map.keys() |> Enum.sort()

  def run(names \\ importer_names(), output_dir \\ "tmp/importer_check") do
    Enum.map(names, fn name -> check(name, Path.join(output_dir, name)) end)
  end

  defp check(name, output_dir) do
    {module, function, extra_args} = Map.fetch!(@importers, name)
    File.rm_rf!(output_dir)
    File.mkdir_p!(output_dir)

    Process.put(:importer_check_dir, output_dir)
    Process.put(:importer_check_requests, [])

    args = [
      __MODULE__.RecordingClient
      | Enum.map(extra_args, fn
          :downloader -> __MODULE__.RecordingClient
          argument -> argument
        end)
    ]

    {micro, result} =
      :timer.tc(fn ->
        {:error, {:rollback, result}} =
          Repo.transaction(
            fn -> Repo.rollback({:rollback, apply(module, function, args)}) end,
            timeout: :infinity
          )

        result
      end)

    %{
      name: name,
      duration_s: Float.round(micro / 1_000_000, 1),
      requests: Enum.reverse(Process.get(:importer_check_requests)),
      result: summarize(result)
    }
  rescue
    error ->
      %{name: name, duration_s: 0, requests: [], result: {:crash, Exception.message(error)}}
  end

  defp summarize({:ok, items}) when is_list(items) do
    items = List.flatten(items)
    first = List.first(items)

    {:ok, length(items),
     first && Map.take(first, [:title, :external_id, :geo_point, :published_at, :date_updated])}
  end

  defp summarize({:error, error}) when is_exception(error), do: {:error, Exception.message(error)}
  defp summarize(other), do: {:unexpected, inspect(other, limit: 5)}

  defmodule RecordingClient do
    @moduledoc false
    alias Hierbautberlin.HTTPClient

    def get!(url, headers \\ [], opts \\ []) do
      started = System.monotonic_time(:millisecond)

      response =
        try do
          HTTPClient.get!(url, headers, opts)
        rescue
          error ->
            record(url, "ERROR #{Exception.message(error)}", 0, started)
            reraise error, __STACKTRACE__
        end

      record(url, response.status_code, byte_size(response.body), started)
      save(url, response.body)
      response
    end

    def get(url, io_device) do
      started = System.monotonic_time(:millisecond)
      result = HTTPClient.get(url, io_device)
      record(url, "download", 0, started)
      result
    end

    defp record(url, status, bytes, started) do
      request = %{
        url: url,
        status: status,
        bytes: bytes,
        ms: System.monotonic_time(:millisecond) - started
      }

      Process.put(:importer_check_requests, [request | Process.get(:importer_check_requests, [])])
    end

    defp save(url, body) do
      dir = Process.get(:importer_check_dir)
      count = length(Process.get(:importer_check_requests, []))

      name =
        url
        |> URI.parse()
        |> then(&"#{&1.host}#{&1.path}")
        |> String.replace(~r/[^\w.-]+/, "_")
        |> String.slice(0, 120)

      if dir && count <= 20, do: File.write!(Path.join(dir, "#{count}_#{name}"), body)
    end
  end
end
