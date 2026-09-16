defmodule HierbautberlinWeb.UserRegistrationControllerTest do
  use HierbautberlinWeb.ConnCase, async: true

  import Hierbautberlin.AccountsFixtures

  alias Hierbautberlin.Repo
  alias Hierbautberlin.Accounts.User
  alias HierbautberlinWeb.FormProtection

  describe "GET /users/register" do
    test "renders registration page", %{conn: conn} do
      conn = get(conn, ~p"/users/register")
      response = html_response(conn, 200)
      assert response =~ "<h1>Registrieren</h1>"
      assert response =~ ~r/Anmelden\s*<\/a>/
      assert response =~ ~r/Registrieren\s*<\/a>/
      assert response =~ ~s(name="form_token")
      assert response =~ ~s(name="website")
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
        post(
          conn,
          ~p"/users/register",
          protected_form_params(valid_user_attributes(email: email))
        )

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
        post(
          conn,
          ~p"/users/register",
          protected_form_params(%{"email" => "with spaces", "password" => "short"})
        )

      response = html_response(conn, 200)
      assert response =~ "<h1>Registrieren</h1>"
      assert response =~ "muss ein @-Zeichen und keine Leerzeichen haben"
      assert response =~ "sollte mindestens 8 Zeichen haben"
    end

    @tag :capture_log
    test "pretends success but creates no account when the honeypot is filled in", %{conn: conn} do
      email = unique_user_email()

      params =
        protected_form_params(valid_user_attributes(email: email))
        |> Map.put("website", "http://spam")

      conn = post(conn, ~p"/users/register", params)

      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Konto erfolgreich angelegt."
      refute get_session(conn, :user_token)
      refute Repo.get_by(User, email: email)
    end

    @tag :capture_log
    test "rejects a form that was submitted too fast", %{conn: conn} do
      email = unique_user_email()

      params =
        valid_user_attributes(email: email)
        |> protected_form_params()
        |> Map.put("form_token", FormProtection.token())

      conn = post(conn, ~p"/users/register", params)

      response = html_response(conn, 200)
      assert response =~ "Bitte sende das Formular noch einmal ab."
      assert response =~ email
      refute Repo.get_by(User, email: email)
    end

    @tag :capture_log
    test "rejects a form without a valid token", %{conn: conn} do
      email = unique_user_email()
      user_params = valid_user_attributes(email: email)

      for params <- [
            %{"user" => user_params},
            protected_form_params(user_params) |> Map.put("form_token", "forged")
          ] do
        conn = post(conn, ~p"/users/register", params)
        assert html_response(conn, 200) =~ "Bitte sende das Formular noch einmal ab."
      end

      refute Repo.get_by(User, email: email)
    end
  end
end
