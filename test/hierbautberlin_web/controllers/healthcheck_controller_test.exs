defmodule HierbautberlinWeb.HealthcheckControllerTest do
  use HierbautberlinWeb.ConnCase, async: true

  describe "GET /ping" do
    test "renders health page", %{conn: conn} do
      conn = get(conn, ~p"/ping")
      assert response(conn, 200) =~ "OK"
    end
  end
end
