defmodule HierbautberlinWeb.EmailTemplates do
  @moduledoc """
  HTML and text templates for emails.
  """
  use HierbautberlinWeb, :html

  embed_templates "templates/*.html", suffix: "_html"
  embed_templates "templates/*.text", suffix: "_text"

  def layout_html(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="de">
      <head>
        <meta charset="utf-8" />
        <meta http-equiv="X-UA-Compatible" content="IE=edge" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <title>Hier Baut Berlin</title>
        <style>
          <%= Phoenix.HTML.raw(email_css()) %>
        </style>
      </head>
      <body>
        {@inner_content}

        <div class="footer">
          <hr />
          <a href="https://hierbautberlin.de">HierBautBerlin.de</a>
          | <a href="mailto:mail@hierbautberlin.de">E-Mail</a>
          | <a href="https://hierbautberlin.de/impressum">Impressum</a>
        </div>
      </body>
    </html>
    """
  end

  def layout_text(assigns) do
    ~H"""
    {@inner_content}

    ---

    * https://hierbautberlin.de
    * https://hierbautberlin.de/impressum
    * mail@hierbautberlin.de
    """
  end

  defp email_css do
    """
    body { font-weight: 400; color: black; }
    h1 { font-size: 1rem; font-weight: 700; margin-top: 2rem; }
    a { color: #000; }
    p { margin-bottom: 1rem; }
    p.topSpacer { margin-top: 1.5rem; }
    .footer { color: #666965; font-size: 90%; }
    .footer hr { border-bottom: none; border-top: 1px solid #666965; margin: 3rem 0rem 1rem 0rem; }
    .footer a { color: #666965; }
    """
  end
end
