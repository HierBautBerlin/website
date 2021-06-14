defmodule HierbautberlinWeb.HealthcheckController do
  use HierbautberlinWeb, :controller

  def index(conn, _params) do
    send_resp(conn, 200, "OK")
  end
end
