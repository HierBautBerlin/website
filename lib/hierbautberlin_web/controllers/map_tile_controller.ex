defmodule HierbautberlinWeb.MapTileController do
  use HierbautberlinWeb, :controller

  alias Hierbautberlin.GeoData.MapFeatures

  # Tile URLs contain the data version, so they can be cached for a long time.
  # Not in development, where the tiles change without a new version.
  @cache_control if Application.compile_env(:hierbautberlin, :environment) == :dev,
                   do: "no-store",
                   else: "public, max-age=86400"

  def show(conn, %{"z" => z, "x" => x, "y" => y}) do
    with {z, ""} <- Integer.parse(z),
         {x, ""} <- Integer.parse(x),
         {y, _extension} <- Integer.parse(y),
         true <- z in 0..30 and x in 0..(2 ** z - 1) and y in 0..(2 ** z - 1) do
      conn
      |> put_resp_header("cache-control", @cache_control)
      |> send_tile(MapFeatures.tile(z, x, y))
    else
      _ -> send_resp(conn, 400, "invalid tile coordinates")
    end
  end

  defp send_tile(conn, <<>>), do: send_resp(conn, 204, "")

  defp send_tile(conn, tile) do
    conn
    |> put_resp_content_type("application/vnd.mapbox-vector-tile", nil)
    |> send_resp(200, tile)
  end
end
