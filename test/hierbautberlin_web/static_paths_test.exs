defmodule HierbautberlinWeb.StaticPathsTest do
  @moduledoc """
  `mix phx.digest` renames the files in the root of priv/static
  (favicon.ico -> favicon-<hash>.ico) and the pages link to the renamed file.
  Plug.Static only serves those because of `:only_matching`, without it the
  favicon is a 404 in production and Firefox shows no icon at all.
  """
  use ExUnit.Case, async: true

  @digested_favicon "favicon-1f42b6278589c5810e1a435c9cda8c1b.ico"

  test "every file in the root of priv/static is covered by a prefix" do
    root_files = Enum.filter(HierbautberlinWeb.static_paths(), &String.contains?(&1, "."))
    prefixes = HierbautberlinWeb.static_path_prefixes()

    for file <- root_files do
      # favicon.ico is served as favicon-<hash>.ico
      digested_start = Path.rootname(file) <> "-"

      assert Enum.any?(prefixes, &String.starts_with?(digested_start, &1)),
             "#{file} needs a prefix in HierbautberlinWeb.static_path_prefixes/0, " <>
               "its digested name is not served otherwise"
    end
  end

  @tag :tmp_dir
  test "the digested files in the root are served, other files are not", %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, "favicon.ico"), "icon")
    File.write!(Path.join(tmp_dir, @digested_favicon), "icon")
    File.write!(Path.join(tmp_dir, "dump.sql"), "no static file")

    assert served?(tmp_dir, "/" <> @digested_favicon)
    assert served?(tmp_dir, "/favicon.ico")
    refute served?(tmp_dir, "/dump.sql")
  end

  defp served?(dir, path) do
    opts =
      Plug.Static.init(
        at: "/",
        from: dir,
        only: HierbautberlinWeb.static_paths(),
        only_matching: HierbautberlinWeb.static_path_prefixes()
      )

    conn = Plug.Static.call(Plug.Test.conn(:get, path <> "?vsn=d"), opts)

    conn.halted and conn.status == 200
  end
end
