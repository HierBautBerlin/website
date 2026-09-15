defmodule HierbautberlinWeb.UserSettingsController do
  use HierbautberlinWeb, :controller

  alias Hierbautberlin.Accounts
  alias Hierbautberlin.Accounts.User
  alias HierbautberlinWeb.UserAuth

  plug :assign_email_and_password_changesets

  def edit(%{assigns: %{current_user: current_user}} = conn, _params) do
    current_user = Accounts.with_subscriptions(current_user)

    render(conn, :edit,
      current_user: current_user,
      page_title: "Einstellungen"
    )
  end

  def update(conn, %{"action" => "update_email"} = params) do
    %{"current_password" => password, "user" => user_params} = params
    %User{} = user = conn.assigns.current_user

    case Accounts.apply_user_email(user, password, user_params) do
      {:ok, applied_user} ->
        Accounts.deliver_update_email_instructions(
          applied_user,
          user.email,
          fn token -> url(~p"/users/settings/confirm_email/#{token}") end
        )

        conn
        |> put_flash(
          :info,
          "Ein Link zur Bestätigung der neuen Email-Adresse ist an die neue Adresse verschickt worden."
        )
        |> redirect(to: ~p"/users/settings")

      {:error, changeset} ->
        current_user = Accounts.with_subscriptions(user)
        render(conn, :edit, email_changeset: changeset, current_user: current_user)
    end
  end

  def update(conn, %{"action" => "update_password"} = params) do
    %{"current_password" => password, "user" => user_params} = params
    user = conn.assigns.current_user

    case Accounts.update_user_password(user, password, user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Passwort erfolgreich aktualisiert.")
        |> put_session(:user_return_to, ~p"/users/settings")
        |> UserAuth.log_in_user(user)

      {:error, changeset} ->
        current_user = Accounts.with_subscriptions(user)
        render(conn, :edit, password_changeset: changeset, current_user: current_user)
    end
  end

  @spec delete(Plug.Conn.t(), any) :: Plug.Conn.t()
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
        |> redirect(to: ~p"/users/settings")
    end
  end

  def confirm_email(conn, %{"token" => token}) do
    case Accounts.update_user_email(conn.assigns.current_user, token) do
      :ok ->
        conn
        |> put_flash(:info, "Email erfolgreich aktualisiert.")
        |> redirect(to: ~p"/users/settings")

      :error ->
        conn
        |> put_flash(:error, "Email-Aktualisierungslink ist leider veraltet.")
        |> redirect(to: ~p"/users/settings")
    end
  end

  defp assign_email_and_password_changesets(conn, _opts) do
    user = conn.assigns.current_user

    conn
    |> assign(:email_changeset, Accounts.change_user_email(user))
    |> assign(:password_changeset, Accounts.change_user_password(user))
  end
end
