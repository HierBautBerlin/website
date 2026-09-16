defmodule HierbautberlinWeb.UserRegistrationController do
  use HierbautberlinWeb, :controller

  alias Hierbautberlin.Accounts
  alias Hierbautberlin.Accounts.User
  alias HierbautberlinWeb.FormProtection
  alias HierbautberlinWeb.UserAuth

  def new(conn, _params) do
    changeset = Accounts.change_user_registration(%User{})
    render(conn, :new, changeset: changeset, page_title: "Registrieren")
  end

  def create(conn, %{"user" => user_params} = params) do
    case FormProtection.check(params, "registration") do
      :ok ->
        register(conn, user_params)

      # looks like a success, so the bot doesn't learn anything
      {:error, :honeypot} ->
        conn
        |> put_flash(:info, "Konto erfolgreich angelegt.")
        |> redirect(to: ~p"/")

      # too fast or an old form: a person just submits the fresh form again
      {:error, _reason} ->
        changeset = Accounts.change_user_registration(%User{}, user_params)

        conn
        |> put_flash(:error, "Bitte sende das Formular noch einmal ab.")
        |> render(:new, changeset: changeset, page_title: "Registrieren")
    end
  end

  defp register(conn, user_params) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_user_confirmation_instructions(
            user,
            fn token -> url(~p"/users/confirm/#{token}") end
          )

        conn
        |> put_flash(:info, "Konto erfolgreich angelegt.")
        |> UserAuth.log_in_user(user)

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset, page_title: "Registrieren")
    end
  end
end
