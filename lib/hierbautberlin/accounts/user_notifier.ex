defmodule Hierbautberlin.Accounts.UserNotifier do
  defp deliver(to, subject, html_body, text_body) do
    require Logger
    Logger.debug(text_body)

    to
    |> HierbautberlinWeb.Email.default_email(subject, html_body, text_body)
    |> HierbautberlinWeb.Mailer.deliver_later()
  end

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(user, url) do
    deliver(
      user,
      "Konto bestätigen",
      """
      <p>Hi #{user.email},</p>

      <p>
      Du kannst dein Konto <a href="#{url}">hier bestätigen</a>.
      </p>

      <p>
      Wenn du dieses Konto nicht selber angelegt hast, ignoriere bitte diese Email.
      </p>
      """,
      """
      Hi #{user.email},

      Du kannst dein Konto bestätigen mit dieser URL:

      #{url}

      Wenn du dieses Konto nicht selber angelegt hast, ignoriere bitte diese Email.
      """
    )
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(
      user,
      "Passwort zurücksetzen",
      """
      <p>Hi #{user.email},</p>

      <p>Du kannst dein Passwort <a href="#{url}">hier zurücksetzen</a>.</p>

      <p>Wenn du diese Änderung nicht selber angefragt hast, ignoriere bitte diese Email.</p>
      """,
      """
      Hi #{user.email},

      Du kannst dein Passwort mit dieser URL zurücksetzen:

      #{url}

      Wenn du diese Änderung nicht selber angefragt hast, ignoriere bitte diese Email.
      """
    )
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(
      user,
      "Email-Adresse ändern",
      """
      <p>Hi #{user.email},</p>

      <p>Du kannst mit dieser URL deine Email <a href="#{url}">hier ändern</a>.</p>

      <p>Wenn du diese Änderung nicht selber angefragt hast, ignoriere bitte diese Email.</p>
      """,
      """
      Hi #{user.email},

      Du kannst mit dieser URL deine Email ändern:

      #{url}

      Wenn du diese Änderung nicht selber angefragt hast, ignoriere bitte diese Email.
      """
    )
  end
end
