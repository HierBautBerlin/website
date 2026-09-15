defmodule Hierbautberlin.Importer.AmtsblattFileNamesTest do
  use Hierbautberlin.DataCase, async: false

  alias Hierbautberlin.FileStorage
  alias Hierbautberlin.GeoData.NewsItem
  alias Hierbautberlin.Importer.AmtsblattFileNames

  setup do
    tmp = Path.join(System.tmp_dir!(), "amtsblatt-#{System.unique_integer([:positive])}.pdf")
    File.write!(tmp, "%PDF")

    names = [
      "amtsblatt/abl_2023_29_3085_3224_online.pdf?ts=1688105763",
      "amtsblatt/abl_2023_16_1705_1760_online.pdf?ts=1680760872",
      "amtsblatt/abl_2023_16_1705_1760_online.pdf"
    ]

    for name <- names, do: FileStorage.store_file(name, tmp, "application/pdf", "Amtsblatt")

    on_exit(fn ->
      File.rm(tmp)

      for name <- names ++ ["amtsblatt/abl_2023_29_3085_3224_online.pdf"] do
        File.rm(FileStorage.path_for_file(name))
      end
    end)

    :ok
  end

  test "moves the files and fixes the links" do
    broken =
      insert(:news_item,
        external_id:
          "/view_pdf/amtsblatt/abl_2023_29_3085_3224_online.pdf?ts=1688105763?page=95&title=A",
        url: "/view_pdf/amtsblatt/abl_2023_29_3085_3224_online.pdf?ts=1688105763?page=95&title=A"
      )

    # issue 16 was imported with and without the timestamp
    duplicate =
      insert(:news_item,
        external_id:
          "/view_pdf/amtsblatt/abl_2023_16_1705_1760_online.pdf?ts=1680760872?page=2&title=B",
        url: "/view_pdf/amtsblatt/abl_2023_16_1705_1760_online.pdf?ts=1680760872?page=2&title=B"
      )

    original =
      insert(:news_item,
        external_id: "/view_pdf/amtsblatt/abl_2023_16_1705_1760_online.pdf?page=2&title=B",
        url: "/view_pdf/amtsblatt/abl_2023_16_1705_1760_online.pdf?page=2&title=B"
      )

    assert %{
             files_moved: 1,
             files_already_existing: 1,
             files_missing: 0,
             news_items_fixed: 1,
             news_items_deleted: 1
           } = AmtsblattFileNames.run()

    assert FileStorage.exists?("amtsblatt/abl_2023_29_3085_3224_online.pdf")
    refute FileStorage.exists?("amtsblatt/abl_2023_29_3085_3224_online.pdf?ts=1688105763")
    assert FileStorage.get_file_by_name("amtsblatt/abl_2023_29_3085_3224_online.pdf")

    assert Repo.reload!(broken).url ==
             "/view_pdf/amtsblatt/abl_2023_29_3085_3224_online.pdf?page=95&title=A"

    refute Repo.get(NewsItem, duplicate.id)
    assert Repo.reload!(original)

    assert %{files_moved: 0, news_items_fixed: 0, news_items_deleted: 0} =
             AmtsblattFileNames.run()
  end
end
