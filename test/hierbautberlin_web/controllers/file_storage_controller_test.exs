defmodule HierbautberlinWeb.FileStorageControllerTest do
  use HierbautberlinWeb.ConnCase, async: true

  describe "GET /filestorage/file.txt" do
    test "renders file", %{conn: conn} do
      File.mkdir_p(Application.get_env(:hierbautberlin, :file_storage_path))

      File.write(
        Path.join(Application.get_env(:hierbautberlin, :file_storage_path), "file.txt"),
        "Hello File!"
      )

      conn = get(conn, ~p"/filestorage/file.txt")
      assert response(conn, 200) =~ "Hello File!"
    end

    test "does not serve files outside of the storage", %{conn: conn} do
      base_path = Application.get_env(:hierbautberlin, :file_storage_path) |> Path.expand()
      sibling = base_path <> "_secret"
      File.mkdir_p!(sibling)
      File.write!(Path.join(sibling, "secret.txt"), "secret")
      on_exit(fn -> File.rm_rf(sibling) end)

      name = Path.basename(sibling)
      assert conn |> get("/filestorage/../#{name}/secret.txt") |> response(404)
      assert conn |> get("/filestorage/%2E%2E/#{name}/secret.txt") |> response(404)
    end

    test "returns 404 if file not present", %{conn: conn} do
      conn = get(conn, ~p"/filestorage/not_found.txt")
      assert response(conn, 404)
    end
  end
end
