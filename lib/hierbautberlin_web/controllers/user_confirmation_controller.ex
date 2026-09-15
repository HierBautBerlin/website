defmodule HierbautberlinWeb.UserConfirmationController do
  use HierbautberlinWeb, :controller

  alias Hierbautberlin.Accounts

  def new(conn, _params) do
    render(conn, :new, page_title: "Email-Bestätigung")
  end

  def create(conn, %{"user" => %{"email" => email}}) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_confirmation_instructions(
        user,
        fn token -> url(~p"/users/confirm/#{token}") end
      )
    end

    # Regardless of the outcome, show an impartial success/error message.
    conn
    |> put_flash(
      :info,
      "Wenn deine Email-Adresse in unserem System ist und noch nicht bestätigt ist," <>
        "wirst du eine Email von uns mit einer Anleitunb bekommen."
    )
    |> redirect(to: ~p"/map")
  end

  # Do not log in the user after confirmation to avoid a
  # leaked token giving the user access to the account.
  def confirm(conn, %{"token" => token}) do
    case Accounts.confirm_user(token) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Konto erfolgreich bestätigt.")
        |> redirect(to: ~p"/map")

      :error ->
        # If there is a current user and the account was already confirmed,
        # then odds are that the confirmation link was already visited, either
        # by some automation or by the user themselves, so we redirect without
        # a warning message.
        case conn.assigns do
          %{current_user: %{confirmed_at: confirmed_at}} when not is_nil(confirmed_at) ->
            redirect(conn, to: ~p"/map")

          %{} ->
            conn
            |> put_flash(:error, "Konto Bestätigungslink ist leider nicht mehr gültig.")
            |> redirect(to: ~p"/map")
        end
    end
  end
end
