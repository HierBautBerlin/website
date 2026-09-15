defmodule HierbautberlinWeb.ImpressumController do
  use HierbautberlinWeb, :controller

  def index(conn, _params) do
    render(conn, :index, page_title: "Impressum")
  end
end
