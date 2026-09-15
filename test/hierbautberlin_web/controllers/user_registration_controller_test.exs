defmodule HierbautberlinWeb.UserRegistrationControllerTest do
  use HierbautberlinWeb.ConnCase, async: true

  import Hierbautberlin.AccountsFixtures

  describe "GET /users/register" do
    test "renders registration page", %{conn: conn} do
      conn = get(conn, ~p"/users/register")
      response = html_response(conn, 200)
      assert response =~ "<h1>Registrieren</h1>"
      assert response =~ ~r/Anmelden\s*<\/a>/
      assert response =~ ~r/Registrieren\s*<\/a>/
    end

    test "redirects if already logged in", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/users/register")
      assert redirected_to(conn) == "/map"
    end
  end

  describe "POST /users/register" do
    @tag :capture_log
    test "creates account and logs the user in", %{conn: conn} do
      email = unique_user_email()

      conn =
        post(conn, ~p"/users/register", %{
          "user" => valid_user_attributes(email: email)
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) =~ "/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/map")
      response = html_response(conn, 200)
      assert response =~ ~r/Einstellungen\s*<\/a>/
      assert response =~ ~r/Abmelden\s*<\/a>/
    end

    test "render errors for invalid data", %{conn: conn} do
      conn =
        post(conn, ~p"/users/register", %{
          "user" => %{"email" => "with spaces", "password" => "short"}
        })

      response = html_response(conn, 200)
      assert response =~ "<h1>Registrieren</h1>"
      assert response =~ "muss ein @-Zeichen und keine Leerzeichen haben"
      assert response =~ "sollte mindestens 8 Zeichen haben"
    end
  end
end
