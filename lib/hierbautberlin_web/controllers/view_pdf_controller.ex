defmodule HierbautberlinWeb.ViewPDFController do
  use HierbautberlinWeb, :controller
  alias Hierbautberlin.FileStorage

  # Links to the Amtsblatt issues from April to June 2023 contain the timestamp
  # berlin.de added to the PDF links: "…online.pdf?ts=1681452185?page=106&title=…".
  # The files and news items are renamed by Hierbautberlin.Importer.AmtsblattFileNames,
  # old links (e.g. in sent emails) are redirected to the link without timestamp.
  def show(conn, %{"path" => path, "ts" => timestamp} = params) do
    query =
      timestamp
      |> String.replace(~r/^\d*\??/, "")
      |> URI.decode_query(Map.drop(params, ["path", "ts"]))

    conn
    |> put_status(:moved_permanently)
    |> redirect(to: ~p"/view_pdf/#{path}?#{query}")
  end

  # the page to open is read from the URL by assets/js/pdfViewer.ts
  def show(conn, %{"path" => path}) do
    file = path |> Path.join() |> FileStorage.get_file_by_name!()

    conn
    |> put_root_layout(html: {HierbautberlinWeb.Layouts, :full_width})
    |> render(:show, file: file, page_title: file.title)
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_status(404)
      |> put_view(html: HierbautberlinWeb.ErrorHTML)
      |> render(:"404")
  end
end
