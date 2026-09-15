defmodule Hierbautberlin.HTTPClient do
  @moduledoc """
  Small HTTP client used by the importers.

  It keeps the `get!/3` shape (a map with `:status_code`, `:body` and `:headers`)
  the importers and their test mocks rely on.
  """

  def get!(url, headers \\ [], opts \\ []) do
    response =
      Req.get!(url,
        headers: normalize_headers(headers),
        receive_timeout: Keyword.get(opts, :recv_timeout, 60_000),
        connect_options: [timeout: Keyword.get(opts, :timeout, 60_000)],
        decode_body: false,
        retry: false
      )

    %{status_code: response.status, body: response.body, headers: response.headers}
  end

  @doc """
  Downloads `url` and writes the body into the already opened `io_device`.
  """
  def get(url, io_device) do
    Req.get!(url,
      into: fn {:data, data}, {req, resp} ->
        IO.binwrite(io_device, data)
        {:cont, {req, resp}}
      end,
      receive_timeout: 120_000,
      decode_body: false
    )

    :ok
  end

  defp normalize_headers(headers) do
    Enum.map(headers, fn {key, value} -> {to_string(key), to_string(value)} end)
  end
end
