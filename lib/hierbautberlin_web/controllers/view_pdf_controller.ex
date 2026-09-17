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

  # The page to open is read from the URL by assets/js/pdfViewer.ts, the title
  # is the entry that links to the page
  def show(conn, %{"path" => path} = params) do
    file = path |> Path.join() |> FileStorage.get_file_by_name!()

    conn
    |> put_root_layout(html: {HierbautberlinWeb.Layouts, :full_width})
    |> render(:show,
      file: file,
      url: FileStorage.url_for_file(file),
      download_name: Path.basename(file.name),
      entry_title: entry_title(params["title"]),
      page_title: file.title
    )
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_status(404)
      |> put_view(html: HierbautberlinWeb.ErrorHTML)
      |> render(:"404")
  end

  defp entry_title(title) when is_binary(title) do
    case String.trim(title) do
      "" -> nil
      title -> title
    end
  end

  defp entry_title(_title), do: nil
end
