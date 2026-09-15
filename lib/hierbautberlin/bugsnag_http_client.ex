defmodule Hierbautberlin.BugsnagHTTPClient do
  @moduledoc """
  `Req` based HTTP adapter for Bugsnag, so we don't need Hierbautberlin.HTTPClient.
  """

  @behaviour Bugsnag.HTTPClient

  alias Bugsnag.HTTPClient.{Request, Response}

  @impl true
  def post(%Request{} = request) do
    case Req.post(request.url, body: request.body, headers: request.headers, retry: false) do
      {:ok, response} -> {:ok, Response.new(response.status, response.headers, response.body)}
      {:error, reason} -> {:error, reason}
    end
  end
end
