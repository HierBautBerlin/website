defmodule HierbautberlinWeb.UserConfirmationController do
  use HierbautberlinWeb, :controller

  alias Hierbautberlin.Accounts
  alias HierbautberlinWeb.FormProtection

  def new(conn, _params) do
    render_new(conn, %{})
  end

  def create(conn, %{"user" => %{"email" => email} = user_params} = params) do
    case FormProtection.check(params, "confirmation") do
      :ok ->
        deliver_confirmation_instructions(email)
        impartial_response(conn)

      # looks like a success, so the bot doesn't learn anything
      {:error, :honeypot} ->
        impartial_response(conn)

      # too fast or an old form: a person just submits the fresh form again
      {:error, _reason} ->
        conn
        |> put_flash(:error, "Bitte sende das Formular noch einmal ab.")
        |> render_new(user_params)
    end
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

  defp deliver_confirmation_instructions(email) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_confirmation_instructions(
        user,
        fn token -> url(~p"/users/confirm/#{token}") end
      )
    end
  end

  defp render_new(conn, user_params) do
    render(conn, :new,
      form: Phoenix.Component.to_form(user_params, as: :user),
      page_title: "Email-Bestätigung"
    )
  end

  # Regardless of the outcome, show an impartial success/error message.
  defp impartial_response(conn) do
    conn
    |> put_flash(
      :info,
      "Wenn deine Email-Adresse in unserem System ist und noch nicht bestätigt ist, " <>
        "wirst du eine Email von uns mit einer Anleitung bekommen."
    )
    |> redirect(to: ~p"/map")
  end
end
