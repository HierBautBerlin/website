defmodule HierbautberlinWeb.ViewPDFController do
  use HierbautberlinWeb, :controller
  alias Hierbautberlin.FileStorage

  def show(conn, %{"path" => url_path, "page" => page, "title" => text}) do
    file = url_path |> Path.join() |> FileStorage.get_file_by_name!()
    render(conn, "show.html", %{file: file, page: page, text: text})
  end
end
