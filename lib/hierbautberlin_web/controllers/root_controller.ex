defmodule HierbautberlinWeb.RootController do
  use HierbautberlinWeb, :controller

  # There is no landing page, the map is the start page
  def index(conn, _params) do
    path = if conn.query_string == "", do: ~p"/map", else: ~p"/map" <> "?" <> conn.query_string
    redirect(conn, to: path)
  end
end
