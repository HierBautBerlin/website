defmodule Hierbautberlin.Importer.VIZ do
  @moduledoc """
  Imports the messages of the Verkehrsinformationszentrale Berlin
  (https://viz.berlin.de): road closures, construction sites, night works and
  changes in public transport.

  `/feed/` returns the ten newest messages as JSON: title, url, date and an
  excerpt of about 700 characters. The excerpt is the text that is analyzed - the
  article pages themselves are not readable for us, a web application firewall
  (Sucuri) answers every request for a page with a redirect to a JavaScript
  challenge, no matter which headers we send. Only `/feed/` is served. That costs
  about a seventh of the locations: measured against the messages of nine months,
  78% can be placed on the map with the whole article and 65% with the excerpt.

  `robots.txt` only excludes `/suchergebnis/`, and one request per run is all this
  importer needs.

  ## What is left out

  The recurring "Verkehrsvorschau" (see `@skipped_slugs`): it is a digest for one
  day or weekend with streets all over the city, and its url is reused for every
  edition. It would be one item that moves across the whole map every morning.
  The single messages it is made of are published on their own as well.

  ## Dates

  The time in the feed is wrong in its minutes - they are the month ("15:09" for
  a message from September) - the date and the hour are right.
  """
  require Logger

  alias Hierbautberlin.GeoData

  @base_url "https://viz.berlin.de"
  @feed_url "#{@base_url}/feed/"
  @headers ["User-Agent": "hierbautberlin.de"]

  # Url parts of the messages that are not imported, see the moduledoc
  @skipped_slugs ["verkehrsvorschau"]

  def import(http_connection \\ Hierbautberlin.HTTPClient) do
    {:ok, source} =
      GeoData.upsert_source(%{
        short_name: "VIZ",
        name: "Verkehrsinformationszentrale Berlin",
        url: "#{@base_url}/aktuelle-meldungen/",
        copyright: "Verkehrsinformationszentrale Berlin",
        color: "#A78BFF",
        background_color: "#7C4DFF"
      })

    result =
      http_connection
      |> fetch_feed()
      |> parse_feed()
      |> Enum.map(fn entry ->
        GeoData.upsert_news_item!(
          %{
            external_id: entry.url,
            title: entry.title,
            url: entry.url,
            content: entry.excerpt,
            published_at: entry.published_at,
            source_id: source.id
          },
          Enum.join([entry.title, entry.excerpt], "\n"),
          []
        )
      end)

    {:ok, result}
  rescue
    error ->
      Bugsnag.report(error)
      {:error, error}
  end

  @doc """
  The messages of the JSON feed. Messages without a title, url or date and the
  ones of `@skipped_slugs` are left out.
  """
  def parse_feed(nil), do: []

  def parse_feed(body) do
    body
    |> Jason.decode!()
    |> List.wrap()
    |> Enum.map(fn entry ->
      %{
        title: entry |> Map.get("title") |> to_string() |> clean(),
        url: entry |> Map.get("url") |> absolute_url(),
        published_at: entry |> Map.get("date") |> parse_datetime(),
        excerpt: entry |> Map.get("excerpt") |> to_string() |> clean() |> presence()
      }
    end)
    |> Enum.filter(&entry?/1)
    |> Enum.uniq_by(& &1.url)
  end

  defp entry?(entry) do
    entry.title != "" && entry.published_at && is_binary(entry.url) &&
      String.starts_with?(entry.url, @base_url) &&
      not Enum.any?(@skipped_slugs, &String.contains?(entry.url, &1))
  end

  defp clean(text) do
    text
    |> String.replace(" ", " ")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp presence(""), do: nil
  defp presence(text), do: text

  # "2026-09-25T15:09:00" in Berlin time
  defp parse_datetime(nil), do: nil

  defp parse_datetime(datetime) do
    with {:ok, naive} <- NaiveDateTime.from_iso8601(to_string(datetime)),
         {:ok, berlin} <- DateTime.from_naive(naive, "Europe/Berlin") do
      berlin |> DateTime.shift_zone!("Etc/UTC") |> DateTime.truncate(:second)
    else
      _ -> nil
    end
  end

  defp absolute_url(url) do
    case url do
      "http" <> _ -> url
      "/" <> _ -> @base_url <> url
      other -> other
    end
  end

  defp fetch_feed(http_connection) do
    response = http_connection.get!(@feed_url, @headers, timeout: 60_000, recv_timeout: 60_000)

    if response.status_code != 200 do
      Logger.warning("VIZ returned #{response.status_code} for #{@feed_url}")
      nil
    else
      response.body
    end
  end
end
