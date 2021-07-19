defmodule HierbautberlinWeb.ViewPDFControllerTest do
  use HierbautberlinWeb.ConnCase, async: true

  alias Hierbautberlin.FileStorage

  describe "GET /view_pdf/file.txt" do
    test "renders pdf file", %{conn: conn} do
      FileStorage.store_file(
        "this_file_exists.pdf",
        "./test/support/data/amtsblatt/abl_2021_28_2389_2480_online.pdf",
        "application/pdf",
        "Hello Title!"
      )

      conn =
        get(
          conn,
          Routes.view_pdf_path(conn, :show, ["this_file_exists.pdf"], %{
            page: 1,
            title: "Hello Title!"
          })
        )

      assert response(conn, 200) =~ "Hello Title!"

      assert response(conn, 200) =~
               "/filestorage/A154C2456073E64CBE2C/C5F68BBA3DB6F113B2E6/77EEBF27B6FBB35E8FC7/018B/this_file_exists.pdf"
    end

    test "returns a 404", %{conn: conn} do
      conn =
        get(
          conn,
          Routes.view_pdf_path(conn, :show, ["not_found.pdf"], %{page: 1, title: "Hello Title!"})
        )

      assert response(conn, 404)
    end
  end
end
