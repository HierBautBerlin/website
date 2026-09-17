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
          ~p"/view_pdf/this_file_exists.pdf?#{%{page: 1, title: "Hello Title!"}}"
        )

      html = html_response(conn, 200)

      path =
        "/filestorage/A154C2456073E64CBE2C/C5F68BBA3DB6F113B2E6/77EEBF27B6FBB35E8FC7/018B/this_file_exists.pdf"

      assert html =~ ~s(<h1 class="pdf--title">Hello Title!</h1>)
      assert html =~ ~s(data-pdf-path="#{path}")
      # works without JavaScript
      assert html =~ ~s(href="#{path}" download="this_file_exists.pdf")
      # the entry that links to the page
      assert html =~ ~s(<p class="pdf--entry">Hello Title!</p>)
      assert html =~ ~s(<label for="pdf-page" class="visually-hidden">Seite</label>)
    end

    test "renders the first page without page and title", %{conn: conn} do
      FileStorage.store_file(
        "amtsblatt/no_page.pdf",
        "./test/support/data/amtsblatt/abl_2021_28_2389_2480_online.pdf",
        "application/pdf",
        "No Page"
      )

      html = conn |> get(~p"/view_pdf/amtsblatt/no_page.pdf") |> html_response(200)
      assert html =~ "No Page"
      refute html =~ "pdf--entry"
    end

    test "redirects old links with the timestamp of berlin.de", %{conn: conn} do
      conn =
        get(
          conn,
          "/view_pdf/amtsblatt/abl_2023_17_1761_1912_online.pdf?ts=1681452185?page=106&title=Stra%C3%9Fenbenennung"
        )

      assert redirected_to(conn, 301) ==
               "/view_pdf/amtsblatt/abl_2023_17_1761_1912_online.pdf?page=106&title=Stra%C3%9Fenbenennung"
    end

    test "returns a 404", %{conn: conn} do
      conn =
        get(
          conn,
          ~p"/view_pdf/not_found.pdf?#{%{page: 1, title: "Hello Title!"}}"
        )

      assert response(conn, 404)
    end
  end
end
