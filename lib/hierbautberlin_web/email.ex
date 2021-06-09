defmodule HierbautberlinWeb.Email do
  import Bamboo.Email

  def base_email(user) do
    new_email(
      to: user,
      from: "mail@hierbautberlin.de"
    )
  end

  def default_email(user, subject, html_body, text_body) do
    base_email(user)
    |> subject(subject)
    |> text_body(text_body)
    |> html_body(html_body)
  end
end
