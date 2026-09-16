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

  @doc """
  The description meta tag of the page, pages and LiveViews can set
  `:meta_description`.
  """
  def meta_description(assigns) do
    assigns[:meta_description] || default_description()
  end

  @doc """
  The canonical URL of the page, without the parameters that only change what
  the map shows. LiveViews and pages can set `:canonical`.
  """
  def canonical_url(assigns) do
    assigns[:canonical] || base_url() <> assigns.conn.request_path
  end

  @doc """
  The Open Graph and Twitter tags, `:ogtags` overwrites single values.
  """
  def ogtags(assigns) do
    image_url = base_url() <> "/images/hierbautberlin.png"
    description = meta_description(assigns)

    Map.merge(
      %{
        "og:title" => title(assigns),
        "og:description" => description,
        "og:type" => "website",
        "og:image" => image_url,
        "og:url" => canonical_url(assigns),
        "twitter:card" => "summary",
        "twitter:site" => "@hierbautberlin",
        "twitter:description" => description,
        "twitter:image" => String.replace(image_url, "http://", "https://")
      },
      assigns[:ogtags] || %{}
    )
  end

  defp base_url, do: ~p"/" |> url() |> String.trim_trailing("/")

  defp default_description do
    "Was macht die Stadt in meinem Kiez? Warum ist hier eine Baustelle? Was wird demnächst " <>
      "gebaut? Dich interessiert, was in deinem Umfeld passiert? Wo du dich beteiligen kannst? " <>
      "Eventuell sogar mit einer E-Mail-Benachrichtigung, sobald etwas Neues gefunden wird? " <>
      "Dann ist Hier Baut Berlin die Lösung."
  end

  defp title(%{page_title: title}) when not is_nil(title) do
    "Hier Baut Berlin - #{title}"
  end

  defp title(_args) do
    "Hier Baut Berlin"
  end
end
