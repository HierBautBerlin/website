defmodule HierbautberlinWeb.UserRegistrationController do
  use HierbautberlinWeb, :controller

  alias Hierbautberlin.Accounts
  alias Hierbautberlin.Accounts.User
  alias HierbautberlinWeb.UserAuth

  def new(conn, _params) do
    changeset = Accounts.change_user_registration(%User{})
    render(conn, "new.html", changeset: changeset, page_title: "Registrieren")
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_user_confirmation_instructions(
            user,
            &Routes.user_confirmation_url(conn, :confirm, &1)
          )

        conn
        |> put_flash(:info, "Konto erfolgreich angelegt.")
        |> UserAuth.log_in_user(user)

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html", changeset: changeset, page_title: "Registrieren")
    end
  end
end
