defmodule Hierbautberlin.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children =
      if Application.get_env(:hierbautberlin, :data_importer) do
        [
          # Start the Ecto repository
          Hierbautberlin.Repo,
          {Hierbautberlin.GeoData.AnalyzeText, name: Hierbautberlin.GeoData.AnalyzeText}
        ]
      else
        jobs = [
          # Start the Ecto repository
          Hierbautberlin.Repo,
          # Start the Telemetry supervisor
          HierbautberlinWeb.Telemetry,
          # Start the PubSub system
          {Phoenix.PubSub, name: Hierbautberlin.PubSub},
          # Start the Endpoint (http/https)
          HierbautberlinWeb.Endpoint
        ]

        if false && Application.get_env(:hierbautberlin, :environment) == :dev do
          jobs
        else
          jobs ++
            [
              # Text parser
              {Hierbautberlin.GeoData.AnalyzeText, name: Hierbautberlin.GeoData.AnalyzeText},
              # Start a worker by calling: Hierbautberlin.Worker.start_link(arg)
              {Hierbautberlin.Importer.ImporterCronjobDaily, []},
              {Hierbautberlin.Importer.ImporterCronjobHourly, []}
            ]
        end
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Hierbautberlin.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    HierbautberlinWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
