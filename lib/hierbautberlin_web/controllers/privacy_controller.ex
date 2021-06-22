defmodule HierbautberlinWeb.PrivacyController do
  use HierbautberlinWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html", page_title: "Datenschutz")
  end
end
