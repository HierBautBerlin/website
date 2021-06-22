defmodule HierbautberlinWeb.LayoutView do
  use HierbautberlinWeb, :view

  alias Phoenix.HTML
  alias HierbautberlinWeb.Router.Helpers

  def ogtags(conn) do
    description = """
    Was macht die Stadt in meinem Kiez? Warum ist hier eine Baustelle? Was wird demnächst gebaut?
    Dich interessiert, was in deinem Umfeld passiert? Wo du dich beteiligen kannst? Eventuell
    sogar mit einer E-Mail-Benachrichtigung, sobald etwas Neues gefunden wird? Dann ist
    Hier Baut Berlin die Lösung.
    """

    image_url = Helpers.url(conn) <> "/images/hierbautberlin.png"

    ogtags =
      Map.merge(
        %{
          "og:title" => title(conn),
          "og:description" => String.replace(description, "\n", " "),
          "og:type" => "website",
          "og:image" => image_url,
          "og:url" => Helpers.url(conn) <> conn.request_path,
          "twitter:card" => "summary",
          "twitter:site" => "@hierbautberlin",
          "twitter:description" => "Wir zeigen dir, was in Berlin passiert.",
          "twitter:image" => String.replace(image_url, "http://", "https://")
        },
        conn.assigns[:ogtags] || %{}
      )

    render_metatags(ogtags)
  end

  defp render_metatags(tags) do
    for {key, value} <- tags do
      {:safe, safe_value} = HTML.html_escape(value)
      raw("<meta property='#{key}' content='#{safe_value}'>\n")
    end
  end

  defp title(%{assigns: %{page_title: title}}) do
    "Hier Baut Berlin - #{title}"
  end

  defp title(_args) do
    "Hier Baut Berlin"
  end
end
