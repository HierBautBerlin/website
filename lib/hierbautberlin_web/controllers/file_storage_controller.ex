defmodule HierbautberlinWeb.FileStorageController do
  use HierbautberlinWeb, :controller

  def show(conn, %{"path" => url_path}) do
    base_path = Application.get_env(:hierbautberlin, :file_storage_path) |> Path.expand()
    file = Path.join(base_path, Path.join(url_path)) |> Path.expand()

    # the trailing slash keeps sibling directories like "file_storage_old" out
    if String.starts_with?(file, base_path <> "/") && File.regular?(file) do
      send_file(conn, 200, file)
    else
      conn
      |> put_status(404)
      |> text("File not found")
    end
  end
end
