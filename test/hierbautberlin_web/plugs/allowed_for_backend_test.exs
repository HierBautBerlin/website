defmodule HierbautberlinWeb.Plugs.AllowedForBackendTest do
  use HierbautberlinWeb.ConnCase, async: true

  import Hierbautberlin.AccountsFixtures

  test "user is redirected when authentication fails", %{conn: conn} do
    conn =
      conn
      |> with_pipeline
      |> HierbautberlinWeb.Plugs.AllowedForBackend.call(%{})

    assert Phoenix.Controller.get_flash(conn, :error) == "Leider musst du ein Admin sein."
    assert redirected_to(conn) == "/"
  end

  test "user can open page if admin", %{conn: conn} do
    user = admin_fixture()

    conn =
      conn
      |> log_in_user(user)
      |> with_pipeline
      |> HierbautberlinWeb.Plugs.AllowedForBackend.call(%{})

    assert Phoenix.Controller.get_flash(conn, :error) == nil
  end

  defp with_pipeline(conn) do
    conn
    |> bypass_through(HierbautberlinWeb.Router, [:browser])
    |> get("/dashboard")
  end
end
