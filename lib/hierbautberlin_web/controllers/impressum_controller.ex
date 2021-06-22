defmodule HierbautberlinWeb.ImpressumController do
  use HierbautberlinWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html", page_title: "Impressum")
  end
end
