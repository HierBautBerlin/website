defmodule HierbautberlinWeb.RedirectToMapController do
  use HierbautberlinWeb, :controller

  def index(conn, _params) do
    redirect(conn, to: "/map")
  end
end
