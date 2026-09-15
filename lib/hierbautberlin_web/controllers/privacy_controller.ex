defmodule HierbautberlinWeb.PrivacyController do
  use HierbautberlinWeb, :controller

  def index(conn, _params) do
    render(conn, :index, page_title: "Datenschutz")
  end
end
