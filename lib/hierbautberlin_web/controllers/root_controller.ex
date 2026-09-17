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

  # The statistics (Plausible, see the root layout) count entries as
  # /map/eintrag/:type/:id, so these paths open the entry on the map
  def entry(conn, %{"type" => type, "id" => id}) do
    redirect(conn, to: ~p"/map?#{[details: id, detailsType: type]}")
  end
end
