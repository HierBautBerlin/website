defmodule HierbautberlinWeb.ViewPDFController do
  use HierbautberlinWeb, :controller
  alias Hierbautberlin.FileStorage

  def show(conn, %{"path" => url_path, "page" => page, "title" => text}) do
    file = url_path |> Path.join() |> FileStorage.get_file_by_name!()
    render(conn, "show.html", %{file: file, page: page, text: text, page_title: file.title})
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_status(404)
      |> put_view(HierbautberlinWeb.ErrorView)
      |> render("404.html", %{})
  end
end
