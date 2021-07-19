defmodule HierbautberlinWeb.FileStorageControllerTest do
  use HierbautberlinWeb.ConnCase, async: true

  describe "GET /filestorage/file.txt" do
    test "renders file", %{conn: conn} do
      File.mkdir_p(Application.get_env(:hierbautberlin, :file_storage_path))

      File.write(
        Path.join(Application.get_env(:hierbautberlin, :file_storage_path), "file.txt"),
        "Hello File!"
      )

      conn = get(conn, Routes.file_storage_path(conn, :show, ["file.txt"]))
      assert response(conn, 200) =~ "Hello File!"
    end

    test "returns 404 if file not present", %{conn: conn} do
      conn = get(conn, Routes.file_storage_path(conn, :show, ["not_found.txt"]))
      assert response(conn, 404)
    end
  end
end
