defmodule HierbautberlinWeb.UserResetPasswordControllerTest do
  use HierbautberlinWeb.ConnCase, async: true

  alias Hierbautberlin.Accounts
  alias Hierbautberlin.Repo
  alias HierbautberlinWeb.FormProtection
  import Hierbautberlin.AccountsFixtures

  setup do
    %{user: user_fixture()}
  end

  describe "GET /users/reset_password" do
    test "renders the reset password page", %{conn: conn} do
      conn = get(conn, ~p"/users/reset_password")
      response = html_response(conn, 200)
      assert response =~ "<h1>Passwort vergessen?</h1>"
    end
  end

  describe "POST /users/reset_password" do
    @tag :capture_log
    test "sends a new reset password token", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/reset_password", protected_form_params(%{"email" => user.email}))

      assert redirected_to(conn) == ~p"/map"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Wenn deine Email-Adresse in unserem System"

      assert Repo.get_by!(Accounts.UserToken, user_id: user.id).context == "reset_password"
    end

    test "does not send reset password token if email is invalid", %{conn: conn} do
      conn =
        post(
          conn,
          ~p"/users/reset_password",
          protected_form_params(%{"email" => "unknown@example.com"})
        )

      assert redirected_to(conn) == ~p"/map"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Wenn deine Email-Adresse in unserem System"

      assert Repo.all(Accounts.UserToken) == []
    end

    @tag :capture_log
    test "sends no email but the usual message when the honeypot is filled in", %{
      conn: conn,
      user: user
    } do
      params =
        %{"email" => user.email} |> protected_form_params() |> Map.put("website", "http://spam")

      conn = post(conn, ~p"/users/reset_password", params)

      assert redirected_to(conn) == ~p"/map"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Wenn deine Email-Adresse in unserem System"

      refute Repo.get_by(Accounts.UserToken, user_id: user.id)
    end

    @tag :capture_log
    test "shows the form again when it was submitted too fast or without a token", %{
      conn: conn,
      user: user
    } do
      fast =
        %{"email" => user.email}
        |> protected_form_params()
        |> Map.put("form_token", FormProtection.token())

      for params <- [fast, %{"user" => %{"email" => user.email}}] do
        response = conn |> post(~p"/users/reset_password", params) |> html_response(200)
        assert response =~ "Bitte sende das Formular noch einmal ab."
        assert response =~ user.email
      end

      refute Repo.get_by(Accounts.UserToken, user_id: user.id)
    end
  end

  describe "GET /users/reset_password/:token" do
    setup %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      %{token: token}
    end

    test "renders reset password", %{conn: conn, token: token} do
      conn = get(conn, ~p"/users/reset_password/#{token}")
      assert html_response(conn, 200) =~ "<h1>Passwort zurücksetzen</h1>"
    end

    test "does not render reset password with invalid token", %{conn: conn} do
      conn = get(conn, ~p"/users/reset_password/#{"oops"}")
      assert redirected_to(conn) == ~p"/map"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Passwort-Link ist nicht korrekt oder veraltet."
    end
  end

  describe "PUT /users/reset_password/:token" do
    setup %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      %{token: token}
    end

    test "resets password once", %{conn: conn, user: user, token: token} do
      conn =
        put(conn, ~p"/users/reset_password/#{token}", %{
          "user" => %{
            "password" => "new valid password",
            "password_confirmation" => "new valid password"
          }
        })

      assert redirected_to(conn) == ~p"/users/log_in"
      refute get_session(conn, :user_token)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Passwort erfolgreich zurück gesetzt."

      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "does not reset password on invalid data", %{conn: conn, token: token} do
      conn =
        put(conn, ~p"/users/reset_password/#{token}", %{
          "user" => %{
            "password" => "short",
            "password_confirmation" => "does not match"
          }
        })

      response = html_response(conn, 200)
      assert response =~ "<h1>Passwort zurücksetzen</h1>"
      assert response =~ "sollte mindestens 8 Zeichen haben"
      assert response =~ "stimmt nicht mit dem Passwort überein"
    end

    test "does not reset password with invalid token", %{conn: conn} do
      conn = put(conn, ~p"/users/reset_password/#{"oops"}")
      assert redirected_to(conn) == ~p"/map"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Passwort-Link ist nicht korrekt oder veraltet."
    end
  end
end
