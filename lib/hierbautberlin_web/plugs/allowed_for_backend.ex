defmodule HierbautberlinWeb.Plugs.AllowedForBackend do
  @behaviour Plug
  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2, put_flash: 3]

  def init(opts), do: opts

  def call(%{assigns: %{current_user: %{role: :admin}}} = conn, _opts) do
    conn
  end

  def call(conn, _opts) do
    conn
    |> put_flash(:error, "Leider musst du ein Admin sein.")
    |> redirect(to: "/")
    |> halt()
  end
end
