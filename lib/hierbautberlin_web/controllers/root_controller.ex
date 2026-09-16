defmodule HierbautberlinWeb.RootController do
  use HierbautberlinWeb, :controller

  # There is no landing page, the map is the start page. The redirect is
  # permanent, so search engines index the map and not "/".
  def index(conn, _params) do
    path = if conn.query_string == "", do: ~p"/map", else: ~p"/map" <> "?" <> conn.query_string

    conn
    |> put_status(:moved_permanently)
    |> redirect(to: path)
  end
end
