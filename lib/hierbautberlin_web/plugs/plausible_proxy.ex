defmodule HierbautberlinWeb.Plugs.PlausibleProxy do
  @moduledoc """
  Serves the Plausible script and forwards its events through our own domain,
  so ad blockers that block plausible.io still let us count the visitors (see
  https://plausible.io/docs/proxy/introduction).

    * `GET /js/hbb.js` - the site script from plausible.io, cached for 6 hours
    * `POST /api/hbb-event` - forwarded to https://plausible.io/api/event

  The paths don't contain "plausible" or "analytics", so block lists don't match.
  The event path is also used in `layouts/head.html.heex`.

  The script id is configured with `config :hierbautberlin, :plausible_script`,
  without it tracking is disabled and both paths respond with 404. Runs before
  `Plug.Parsers` in the endpoint, so the event body is forwarded unchanged.
  """
  @behaviour Plug

  import Plug.Conn
  require Logger

  @script_path "/js/hbb.js"
  @event_path "/api/hbb-event"
  @script_max_age_seconds 6 * 60 * 60

  def script_path, do: @script_path
  def event_path, do: @event_path

  @doc "The configured script id (e.g. `pa-XXXX`), nil when tracking is disabled."
  def script_id do
    case Application.get_env(:hierbautberlin, :plausible_script) do
      id when is_binary(id) and id != "" -> id
      _ -> nil
    end
  end

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: "GET", request_path: @script_path} = conn, _opts) do
    with id when is_binary(id) <- script_id(),
         {:ok, script} <- cached_script(id) do
      conn
      |> put_resp_content_type("application/javascript")
      |> put_resp_header("cache-control", "public, max-age=3600")
      |> send_resp(200, script)
      |> halt()
    else
      nil -> conn |> send_resp(404, "") |> halt()
      :error -> conn |> send_resp(502, "") |> halt()
    end
  end

  def call(%Plug.Conn{method: "POST", request_path: @event_path} = conn, _opts) do
    if script_id() do
      forward_event(conn)
    else
      conn |> send_resp(404, "") |> halt()
    end
  end

  def call(conn, _opts), do: conn

  defp forward_event(conn) do
    {:ok, body, conn} = read_body(conn, length: 64_000)

    headers = [
      {"content-type", conn |> get_req_header("content-type") |> List.first("text/plain")},
      {"user-agent", conn |> get_req_header("user-agent") |> List.first("")},
      # Plausible counts unique visitors by IP (hashed, not stored)
      {"x-forwarded-for", forwarded_for(conn)}
    ]

    case Req.post(
           [url: "https://plausible.io/api/event", body: body, headers: headers] ++ req_options()
         ) do
      {:ok, %{status: status, body: body}} ->
        conn |> send_resp(status, if(is_binary(body), do: body, else: "")) |> halt()

      {:error, error} ->
        Logger.warning("Plausible event could not be forwarded: #{inspect(error)}")
        conn |> send_resp(502, "") |> halt()
    end
  end

  # like $proxy_add_x_forwarded_for in nginx: the client address the reverse
  # proxy (Coolify) sent, followed by the address of the direct peer
  defp forwarded_for(conn) do
    peer = conn.remote_ip |> :inet.ntoa() |> to_string()

    case get_req_header(conn, "x-forwarded-for") do
      [forwarded | _] -> forwarded <> ", " <> peer
      [] -> peer
    end
  end

  defp cached_script(id) do
    now = System.monotonic_time(:second)

    case :persistent_term.get({__MODULE__, id}, nil) do
      {script, fetched_at} when now - fetched_at < @script_max_age_seconds ->
        {:ok, script}

      stale ->
        case fetch_script(id) do
          {:ok, script} ->
            :persistent_term.put({__MODULE__, id}, {script, now})
            {:ok, script}

          # plausible.io is not reachable, an older script is better than none
          :error when is_tuple(stale) ->
            {:ok, elem(stale, 0)}

          :error ->
            :error
        end
    end
  end

  defp fetch_script(id) do
    case Req.get([url: "https://plausible.io/js/#{id}.js"] ++ req_options()) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      other ->
        Logger.warning("Plausible script could not be loaded: #{inspect(other)}")
        :error
    end
  end

  defp req_options do
    [retry: false, receive_timeout: 5_000] ++
      Application.get_env(:hierbautberlin, :plausible_req_options, [])
  end
end
