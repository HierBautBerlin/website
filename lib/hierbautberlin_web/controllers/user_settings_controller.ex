defmodule HierbautberlinWeb.UserSettingsController do
  use HierbautberlinWeb, :controller

  alias Hierbautberlin.Accounts
  alias HierbautberlinWeb.UserAuth

  plug :assign_email_and_password_changesets

  def edit(conn, _params) do
    render(conn, "edit.html")
  end

  def update(conn, %{"action" => "update_email"} = params) do
    %{"current_password" => password, "user" => user_params} = params
    user = conn.assigns.current_user

    case Accounts.apply_user_email(user, password, user_params) do
      {:ok, applied_user} ->
        Accounts.deliver_update_email_instructions(
          applied_user,
          user.email,
          &Routes.user_settings_url(conn, :confirm_email, &1)
        )

        conn
        |> put_flash(
          :info,
          "Ein Link zur Bestätigung der neuen Email-Adresse ist an die neue Adresse verschickt worden."
        )
        |> redirect(to: Routes.user_settings_path(conn, :edit))

      {:error, changeset} ->
        render(conn, "edit.html", email_changeset: changeset)
    end
  end

  def update(conn, %{"action" => "update_password"} = params) do
    %{"current_password" => password, "user" => user_params} = params
    user = conn.assigns.current_user

    case Accounts.update_user_password(user, password, user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Passwort erfolgreich aktualisiert.")
        |> put_session(:user_return_to, Routes.user_settings_path(conn, :edit))
        |> UserAuth.log_in_user(user)

      {:error, changeset} ->
        render(conn, "edit.html", password_changeset: changeset)
    end
  end

  def delete(conn, _params) do
    user = conn.assigns.current_user

    case Accounts.delete_user(user) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Konto erfolgreich gelöscht.")
        |> UserAuth.log_out_user()

      {:error, _} ->
        conn
        |> put_flash(:info, "Konto konnte nicht gelöscht werden.")
        |> redirect(to: Routes.user_settings_path(conn, :edit))
    end
  end

  def confirm_email(conn, %{"token" => token}) do
    case Accounts.update_user_email(conn.assigns.current_user, token) do
      :ok ->
        conn
        |> put_flash(:info, "Email erfolgreich aktualisiert.")
        |> redirect(to: Routes.user_settings_path(conn, :edit))

      :error ->
        conn
        |> put_flash(:error, "Email-Aktualisierungslink ist leider veraltet.")
        |> redirect(to: Routes.user_settings_path(conn, :edit))
    end
  end

  defp assign_email_and_password_changesets(conn, _opts) do
    user = conn.assigns.current_user

    conn
    |> assign(:email_changeset, Accounts.change_user_email(user))
    |> assign(:password_changeset, Accounts.change_user_password(user))
  end
end
