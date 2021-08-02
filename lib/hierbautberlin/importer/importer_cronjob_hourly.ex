defmodule Hierbautberlin.Importer.ImporterCronjobHourly do
  use GenServer

  def start_link(state) do
    GenServer.start_link(__MODULE__, state)
  end

  def init(state) do
    schedule_work()
    {:ok, state}
  end

  def handle_info(:work, state) do
    import_start =
      Timex.now()
      |> Timex.shift(minutes: -1)

    Hierbautberlin.Importer.import_hourly()
    Hierbautberlin.NotifySubscription.notify_changes_since(import_start)
    schedule_work()
    {:noreply, state}
  end

  def handle_info(message, state) do
    Bugsnag.report(%RuntimeError{message: "unknown message in analyze_text: #{inspect(message)}"},
      severity: "warning"
    )

    {:ok, state}
  end

  defp schedule_work() do
    Process.send_after(self(), :work, 1_000 * 60 * 60)
  end
end
