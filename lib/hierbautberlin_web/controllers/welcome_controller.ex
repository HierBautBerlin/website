defmodule HierbautberlinWeb.WelcomeController do
  use HierbautberlinWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
