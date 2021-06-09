defmodule HierbautberlinWeb.UserSettingsControllerTest do
  use HierbautberlinWeb.ConnCase, async: true

  alias Hierbautberlin.Accounts
  import Hierbautberlin.AccountsFixtures

  setup :register_and_log_in_user

  describe "GET /users/settings" do
    test "renders settings page", %{conn: conn} do
      conn = get(conn, Routes.user_settings_path(conn, :edit))
      response = html_response(conn, 200)
      assert response =~ "<h1>Einstellungen</h1>"
    end

    test "redirects if user is not logged in" do
      conn = build_conn()
      conn = get(conn, Routes.user_settings_path(conn, :edit))
      assert redirected_to(conn) == Routes.user_session_path(conn, :new)
    end
  end

  describe "PUT /users/settings (change password form)" do
    test "updates the user password and resets tokens", %{conn: conn, user: user} do
      new_password_conn =
        put(conn, Routes.user_settings_path(conn, :update), %{
          "action" => "update_password",
          "current_password" => valid_user_password(),
          "user" => %{
            "password" => "new valid password",
            "password_confirmation" => "new valid password"
          }
        })

      assert redirected_to(new_password_conn) == Routes.user_settings_path(conn, :edit)
      assert get_session(new_password_conn, :user_token) != get_session(conn, :user_token)
      assert get_flash(new_password_conn, :info) =~ "Passwort erfolgreich aktualisiert."
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "does not update password on invalid data", %{conn: conn} do
      old_password_conn =
        put(conn, Routes.user_settings_path(conn, :update), %{
          "action" => "update_password",
          "current_password" => "invalid",
          "user" => %{
            "password" => "short",
            "password_confirmation" => "does not match"
          }
        })

      response = html_response(old_password_conn, 200)
      assert response =~ "<h1>Einstellungen</h1>"
      assert response =~ "sollte mindestens 8 Zeichen haben"
      assert response =~ "stimmt nicht mit dem Passwort überein"
      assert response =~ "ist ungültig"

      assert get_session(old_password_conn, :user_token) == get_session(conn, :user_token)
    end
  end

  describe "PUT /users/settings (change email form)" do
    @tag :capture_log
    test "updates the user email", %{conn: conn, user: user} do
      conn =
        put(conn, Routes.user_settings_path(conn, :update), %{
          "action" => "update_email",
          "current_password" => valid_user_password(),
          "user" => %{"email" => unique_user_email()}
        })

      assert redirected_to(conn) == Routes.user_settings_path(conn, :edit)
      assert get_flash(conn, :info) =~ "Ein Link zur Bestätigung der neuen"
      assert Accounts.get_user_by_email(user.email)
    end

    test "does not update email on invalid data", %{conn: conn} do
      conn =
        put(conn, Routes.user_settings_path(conn, :update), %{
          "action" => "update_email",
          "current_password" => "invalid",
          "user" => %{"email" => "with spaces"}
        })

      response = html_response(conn, 200)
      assert response =~ "<h1>Einstellungen</h1>"
      assert response =~ "muss ein @-Zeichen und keine Leerzeichen haben"
      assert response =~ "ist ungültig"
    end
  end

  describe "DELETE /users/settings (change email form)" do
    test "Deletes the user", %{conn: conn, user: user} do
      conn = delete(conn, Routes.user_settings_path(conn, :delete))

      assert redirected_to(conn) == Routes.welcome_path(conn, :index)
      assert get_flash(conn, :info) =~ "Konto erfolgreich gelöscht."
      assert Accounts.get_user(user.id) == nil
    end
  end

  describe "GET /users/settings/confirm_email/:token" do
    setup %{user: user} do
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{token: token, email: email}
    end

    test "updates the user email once", %{conn: conn, user: user, token: token, email: email} do
      conn = get(conn, Routes.user_settings_path(conn, :confirm_email, token))
      assert redirected_to(conn) == Routes.user_settings_path(conn, :edit)
      assert get_flash(conn, :info) =~ "Email erfolgreich aktualisiert."
      refute Accounts.get_user_by_email(user.email)
      assert Accounts.get_user_by_email(email)

      conn = get(conn, Routes.user_settings_path(conn, :confirm_email, token))
      assert redirected_to(conn) == Routes.user_settings_path(conn, :edit)
      assert get_flash(conn, :error) =~ "Email-Aktualisierungslink ist leider veraltet."
    end

    test "does not update email with invalid token", %{conn: conn, user: user} do
      conn = get(conn, Routes.user_settings_path(conn, :confirm_email, "oops"))
      assert redirected_to(conn) == Routes.user_settings_path(conn, :edit)
      assert get_flash(conn, :error) =~ "Email-Aktualisierungslink ist leider veraltet."
      assert Accounts.get_user_by_email(user.email)
    end

    test "redirects if user is not logged in", %{token: token} do
      conn = build_conn()
      conn = get(conn, Routes.user_settings_path(conn, :confirm_email, token))
      assert redirected_to(conn) == Routes.user_session_path(conn, :new)
    end
  end
end
