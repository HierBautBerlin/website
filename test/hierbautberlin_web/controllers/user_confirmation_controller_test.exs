defmodule HierbautberlinWeb.UserConfirmationControllerTest do
  use HierbautberlinWeb.ConnCase, async: true

  alias Hierbautberlin.Accounts
  alias Hierbautberlin.Repo
  alias HierbautberlinWeb.FormProtection
  import Hierbautberlin.AccountsFixtures

  setup do
    %{user: user_fixture()}
  end

  describe "GET /users/confirm" do
    test "renders the confirmation page", %{conn: conn} do
      conn = get(conn, ~p"/users/confirm")
      response = html_response(conn, 200)
      assert response =~ "<h1>Bestätigungsanweisungen erneut senden</h1>"
    end
  end

  describe "POST /users/confirm" do
    @tag :capture_log
    test "sends a new confirmation token", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/confirm", protected_form_params(%{"email" => user.email}))

      assert redirected_to(conn) == ~p"/map"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Wenn deine Email-Adresse in unserem System ist"

      assert Repo.get_by!(Accounts.UserToken, user_id: user.id).context == "confirm"
    end

    test "does not send confirmation token if User is confirmed", %{conn: conn, user: user} do
      Repo.update!(Accounts.User.confirm_changeset(user))

      conn =
        post(conn, ~p"/users/confirm", protected_form_params(%{"email" => user.email}))

      assert redirected_to(conn) == ~p"/map"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Wenn deine Email-Adresse in unserem System ist"

      refute Repo.get_by(Accounts.UserToken, user_id: user.id)
    end

    test "does not send confirmation token if email is invalid", %{conn: conn} do
      conn =
        post(conn, ~p"/users/confirm", protected_form_params(%{"email" => "unknown@example.com"}))

      assert redirected_to(conn) == ~p"/map"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Wenn deine Email-Adresse in unserem System ist"

      assert Repo.all(Accounts.UserToken) == []
    end

    @tag :capture_log
    test "sends no email but the usual message when the honeypot is filled in", %{
      conn: conn,
      user: user
    } do
      params =
        %{"email" => user.email} |> protected_form_params() |> Map.put("website", "http://spam")

      conn = post(conn, ~p"/users/confirm", params)

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
        response = conn |> post(~p"/users/confirm", params) |> html_response(200)
        assert response =~ "Bitte sende das Formular noch einmal ab."
        assert response =~ user.email
      end

      refute Repo.get_by(Accounts.UserToken, user_id: user.id)
    end
  end

  describe "GET /users/confirm/:token" do
    test "confirms the given token once", %{conn: conn, user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      conn = get(conn, ~p"/users/confirm/#{token}")
      assert redirected_to(conn) == ~p"/map"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Konto erfolgreich bestätigt."
      assert Accounts.get_user!(user.id).confirmed_at
      refute get_session(conn, :user_token)
      assert Repo.all(Accounts.UserToken) == []

      # When not logged in
      conn = get(conn, ~p"/users/confirm/#{token}")
      assert redirected_to(conn) == ~p"/map"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Konto Bestätigungslink ist leider nicht mehr gültig."

      # When logged in
      conn =
        build_conn()
        |> log_in_user(user)
        |> get(~p"/users/confirm/#{token}")

      assert redirected_to(conn) == ~p"/map"
      refute Phoenix.Flash.get(conn.assigns.flash, :error)
    end

    test "does not confirm email with invalid token", %{conn: conn, user: user} do
      conn = get(conn, ~p"/users/confirm/#{"oops"}")
      assert redirected_to(conn) == ~p"/map"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Konto Bestätigungslink ist leider nicht mehr gültig."

      refute Accounts.get_user!(user.id).confirmed_at
    end
  end
end
