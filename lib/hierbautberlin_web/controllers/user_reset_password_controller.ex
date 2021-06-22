defmodule HierbautberlinWeb.UserResetPasswordController do
  use HierbautberlinWeb, :controller

  alias Hierbautberlin.Accounts

  plug :get_user_by_reset_password_token when action in [:edit, :update]

  def new(conn, _params) do
    render(conn, "new.html", page_title: "Passwort vergessen")
  end

  def create(conn, %{"user" => %{"email" => email}}) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(
        user,
        &Routes.user_reset_password_url(conn, :edit, &1)
      )
    end

    # Regardless of the outcome, show an impartial success/error message.
    conn
    |> put_flash(
      :info,
      "Wenn deine Email-Adresse in unserem System ist, wirst du eine Email mit einer Anleitung zum zurücksetzen des Passwortes erhalten."
    )
    |> redirect(to: "/")
  end

  def edit(conn, _params) do
    render(conn, "edit.html",
      changeset: Accounts.change_user_password(conn.assigns.user),
      page_title: "Passwort ändern"
    )
  end

  # Do not log in the user after reset password to avoid a
  # leaked token giving the user access to the account.
  def update(conn, %{"user" => user_params}) do
    case Accounts.reset_user_password(conn.assigns.user, user_params) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Passwort erfolgreich zurück gesetzt.")
        |> redirect(to: Routes.user_session_path(conn, :new))

      {:error, changeset} ->
        render(conn, "edit.html", changeset: changeset, page_title: "Passwort ändern")
    end
  end

  defp get_user_by_reset_password_token(conn, _opts) do
    %{"token" => token} = conn.params

    if user = Accounts.get_user_by_reset_password_token(token) do
      conn |> assign(:user, user) |> assign(:token, token)
    else
      conn
      |> put_flash(:error, "Passwort-Link ist nicht korrekt oder veraltet.")
      |> redirect(to: "/")
      |> halt()
    end
  end
end
