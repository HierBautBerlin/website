defmodule HierbautberlinWeb.Email do
  import Swoosh.Email

  alias HierbautberlinWeb.{EmailTemplates, Mailer}

  @from {"Hier Baut Berlin", "mail@hierbautberlin.de"}

  def base_email(user) do
    new()
    |> to(user.email)
    |> from(@from)
  end

  def default_email(user, subject, html_body, text_body) do
    base_email(user)
    |> subject("Hier Baut Berlin - " <> subject)
    |> text_body(text_body)
    |> html_body(html_body)
  end

  def new_items_found(user, items) do
    assigns = %{items: items}

    email =
      base_email(user)
      |> subject("Hier Baut Berlin - Neue Einträge gefunden")
      |> html_body(render_html(:new_items_found_html, assigns))
      |> text_body(render_text(:new_items_found_text, assigns))

    deliver(email)
  end

  def deliver(email) do
    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  defp render_html(template, assigns) do
    inner = apply(EmailTemplates, template, [assigns])

    %{inner_content: inner}
    |> EmailTemplates.layout_html()
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
    |> Premailex.to_inline_css()
  end

  defp render_text(template, assigns) do
    inner = apply(EmailTemplates, template, [assigns])

    %{inner_content: inner}
    |> EmailTemplates.layout_text()
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
    |> HtmlEntities.decode()
  end
end
