defmodule HierbautberlinWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use HierbautberlinWeb, :controller
      use HierbautberlinWeb, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.
  """

  def static_paths,
    do:
      ~w(css fonts images svg js pdfjs favicon.ico favicon-16x16.png favicon-32x32.png apple-touch-icon.png android-chrome-192x192.png android-chrome-512x512.png site.webmanifest robots.txt)

  @doc """
  Prefixes of the files in the root of priv/static. `mix phx.digest` renames
  them (favicon.ico -> favicon-<hash>.ico) and `~p"/favicon.ico"` links to the
  renamed file, which `static_paths/0` no longer matches. Plug.Static needs
  these prefixes as `:only_matching`, otherwise the digested files are a 404
  (Firefox then shows no favicon at all, Chrome falls back to /favicon.ico).
  """
  def static_path_prefixes, do: ~w(favicon- apple-touch-icon- android-chrome- site- robots-)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]

      use Gettext, backend: HierbautberlinWeb.Gettext

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView

      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      use Gettext, backend: HierbautberlinWeb.Gettext

      # HTML escaping functionality
      import Phoenix.HTML

      import HierbautberlinWeb.CoreComponents
      import HierbautberlinWeb.StateHelpers
      import HierbautberlinWeb.MapRouteHelpers
      import Hierbautberlin.Services.Blank

      alias Phoenix.LiveView.JS
      alias HierbautberlinWeb.Layouts

      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: HierbautberlinWeb.Endpoint,
        router: HierbautberlinWeb.Router,
        statics: HierbautberlinWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/live_view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
