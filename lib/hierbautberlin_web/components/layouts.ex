defmodule HierbautberlinWeb.Layouts do
  @moduledoc """
  Layouts and shared page chrome (head, header, footers).
  """
  use HierbautberlinWeb, :html

  embed_templates "layouts/*"

  @doc """
  Layout for regular (controller rendered) pages.
  """
  attr :flash, :map, required: true
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <main role="main" class="container">
      <.flash_group flash={@flash} />
      {render_slot(@inner_block)}
    </main>
    <.footer />
    """
  end

  @doc """
  Layout for LiveViews.
  """
  attr :flash, :map, required: true
  slot :inner_block, required: true

  def live(assigns) do
    ~H"""
    <div class="live-header"></div>
    <main role="main" class="live-container">
      {render_slot(@inner_block)}
    </main>
    """
  end

  # for aria-current in the menu
  def current_path?(%{conn: %Plug.Conn{request_path: request_path}}, path),
    do: request_path == path

  def current_path?(_assigns, _path), do: false

  def ogtags(conn) do
    description = """
    Was macht die Stadt in meinem Kiez? Warum ist hier eine Baustelle? Was wird demnächst gebaut?
    Dich interessiert, was in deinem Umfeld passiert? Wo du dich beteiligen kannst? Eventuell
    sogar mit einer E-Mail-Benachrichtigung, sobald etwas Neues gefunden wird? Dann ist
    Hier Baut Berlin die Lösung.
    """

    base_url = url(~p"/")
    base_url = String.trim_trailing(base_url, "/")
    image_url = base_url <> "/images/hierbautberlin.png"

    Map.merge(
      %{
        "og:title" => title(conn),
        "og:description" => String.replace(description, "\n", " "),
        "og:type" => "website",
        "og:image" => image_url,
        "og:url" => base_url <> conn.request_path,
        "twitter:card" => "summary",
        "twitter:site" => "@hierbautberlin",
        "twitter:description" => "Wir zeigen dir, was in Berlin passiert.",
        "twitter:image" => String.replace(image_url, "http://", "https://")
      },
      conn.assigns[:ogtags] || %{}
    )
  end

  defp title(%{assigns: %{page_title: title}}) when not is_nil(title) do
    "Hier Baut Berlin - #{title}"
  end

  defp title(_args) do
    "Hier Baut Berlin"
  end
end
