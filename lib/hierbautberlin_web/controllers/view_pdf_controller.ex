defmodule HierbautberlinWeb.ViewPDFController do
  use HierbautberlinWeb, :controller
  alias Hierbautberlin.FileStorage

  def show(conn, %{"path" => url_path, "page" => page, "title" => text}) do
    file = url_path |> Path.join() |> FileStorage.get_file_by_name!()

    conn
    |> put_root_layout(html: {HierbautberlinWeb.Layouts, :full_width})
    |> render(:show, file: file, page: page, text: text, page_title: file.title)
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_status(404)
      |> put_view(html: HierbautberlinWeb.ErrorHTML)
      |> render(:"404")
  end
end
