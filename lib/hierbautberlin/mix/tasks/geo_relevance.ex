defmodule Mix.Tasks.Geo.Relevance do
  use Mix.Task

  @shortdoc "Calculates the relevance of all news items again"

  @moduledoc """
  Calculates the relevance (importance and relevant period) of all news items
  again, see `Hierbautberlin.GeoData.Relevance`. Geo items get theirs from the
  importers.

      mix geo.relevance

  In production use `Hierbautberlin.Release.update_relevance/0`.
  """

  alias Hierbautberlin.GeoData.Relevance

  def run(_args) do
    Mix.Task.run("app.start")
    count = Relevance.update_news_items()
    Mix.shell().info("Updated #{count} news items")
  end
end
