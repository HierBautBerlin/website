defmodule HierbautberlinWeb.Email do
  import Bamboo.Email
  use Bamboo.Phoenix, view: HierbautberlinWeb.EmailView
  alias HierbautberlinWeb.Mailer

  def base_email(user) do
    new_email(
      to: user,
      from: "mail@hierbautberlin.de"
    )
    |> put_layout({HierbautberlinWeb.LayoutView, :email})
  end

  def default_email(user, subject, html_body, text_body) do
    base_email(user)
    |> subject("Hier Baut Berlin - " <> subject)
    |> text_body(text_body)
    |> html_body(html_body)
  end

  def new_items_found(user, items) do
    base_email(user)
    |> subject("Hier Baut Berlin - Neue Einträge gefunden")
    |> assign(:items, items)
    |> render(:new_items_found)
    |> premail()
    |> Mailer.deliver_later()
  end

  defp premail(email) do
    html = Premailex.to_inline_css(email.html_body)

    email
    |> html_body(html)
  end
end
