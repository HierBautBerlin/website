defmodule Hierbautberlin.FileStorageTest do
  use Hierbautberlin.DataCase

  alias Hierbautberlin.FileStorage
  alias Hierbautberlin.FileStorage.FileItem

  describe "files" do
    @valid_attrs %{name: "some name", type: "some type", title: "My File"}
    @update_attrs %{name: "some updated name", type: "some updated type"}
    @invalid_attrs %{name: nil, type: nil}

    def file_fixture(attrs \\ %{}) do
      {:ok, file} =
        attrs
        |> Enum.into(@valid_attrs)
        |> FileStorage.create_file()

      file
    end

    test "list_files/0 returns all files" do
      file = file_fixture()
      assert FileStorage.list_files() == [file]
    end

    test "get_file!/1 returns the file with given id" do
      file = file_fixture()
      assert FileStorage.get_file!(file.id) == file
    end

    test "create_file/1 with valid data creates a file" do
      assert {:ok, %FileItem{} = file} = FileStorage.create_file(@valid_attrs)
      assert file.name == "some name"
      assert file.type == "some type"
    end

    test "create_file/1 run again will overwrite the data" do
      assert {:ok, %FileItem{} = file} = FileStorage.create_file(@valid_attrs)

      assert {:ok, %FileItem{} = file} =
               FileStorage.create_file(%{name: "some name", title: "New Title"})

      assert file.name == "some name"
      assert file.type == "some type"
      assert file.title == "New Title"
    end

    test "create_file/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = FileStorage.create_file(@invalid_attrs)
    end

    test "update_file/2 with valid data updates the file" do
      file = file_fixture()
      assert {:ok, %FileItem{} = file} = FileStorage.update_file(file, @update_attrs)
      assert file.name == "some updated name"
      assert file.type == "some updated type"
    end

    test "update_file/2 with invalid data returns error changeset" do
      file = file_fixture()
      assert {:error, %Ecto.Changeset{}} = FileStorage.update_file(file, @invalid_attrs)
      assert file == FileStorage.get_file!(file.id)
    end

    test "delete_file/1 deletes the file" do
      file = file_fixture()
      assert {:ok, %FileItem{}} = FileStorage.delete_file(file)
      assert_raise Ecto.NoResultsError, fn -> FileStorage.get_file!(file.id) end
    end

    test "change_file/1 returns a file changeset" do
      file = file_fixture()
      assert %Ecto.Changeset{} = FileStorage.change_file(file)
    end
  end

  describe "path_for_file" do
    test "returns a nice filename for a FileItem" do
      assert FileStorage.path_for_file(%FileItem{
               name: "amtsblatt/abl_2021_28_2389_2480_online.pdf"
             }) ==
               "./file_storage/C985239A3E93DBAA4CD5/1A6E0C5B979F8BE5E0CE/99633E8697D62BE66481/5337/abl_2021_28_2389_2480_online.pdf"
    end

    test "returns a nice filename in the storage" do
      assert FileStorage.path_for_file("amtsblatt/abl_2021_28_2389_2480_online.pdf") ==
               "./file_storage/C985239A3E93DBAA4CD5/1A6E0C5B979F8BE5E0CE/99633E8697D62BE66481/5337/abl_2021_28_2389_2480_online.pdf"
    end
  end

  describe "url_for_file" do
    test "returns a nice url for a FileItem" do
      assert FileStorage.url_for_file(%FileItem{
               name: "amtsblatt/abl_2021_28_2389_2480_online.pdf"
             }) ==
               "/filestorage/C985239A3E93DBAA4CD5/1A6E0C5B979F8BE5E0CE/99633E8697D62BE66481/5337/abl_2021_28_2389_2480_online.pdf"
    end

    test "returns a nice url in the storage" do
      assert FileStorage.url_for_file("amtsblatt/abl_2021_28_2389_2480_online.pdf") ==
               "/filestorage/C985239A3E93DBAA4CD5/1A6E0C5B979F8BE5E0CE/99633E8697D62BE66481/5337/abl_2021_28_2389_2480_online.pdf"
    end
  end

  describe "get_file_by_name!/1" do
    test "returns the file with given name" do
      FileStorage.create_file(%{name: "this_file.pdf", type: "some/type", title: "My Title"})

      file_item = FileStorage.get_file_by_name!("this_file.pdf")

      assert file_item.name == "this_file.pdf"
      assert file_item.type == "some/type"
    end

    test "throws error if file does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        FileStorage.get_file_by_name!("wrong.pdf")
      end
    end
  end

  describe "store_file/4" do
    test "stores a file and creates a db entry" do
      File.touch("this_file_exists.pdf")

      FileStorage.store_file(
        "this_file_exists.pdf",
        "this_file_exists.pdf",
        "application/pdf",
        "My File"
      )

      assert FileStorage.exists?("this_file_exists.pdf")

      assert File.exists?(
               "./file_storage/A154C2456073E64CBE2C/C5F68BBA3DB6F113B2E6/77EEBF27B6FBB35E8FC7/018B/this_file_exists.pdf"
             )

      file_item = FileStorage.get_file_by_name!("this_file_exists.pdf")

      assert file_item.name == "this_file_exists.pdf"
      assert file_item.type == "application/pdf"
      assert file_item.title == "My File"

      File.rm("this_file_exists.pdf")
    end

    test "overwrites a already existing file" do
      File.touch("dublicate.pdf")

      FileStorage.store_file(
        "dublicate.pdf",
        "dublicate.pdf",
        "application/pdf",
        "Old Title"
      )

      File.touch("dublicate.pdf")

      FileStorage.store_file(
        "dublicate.pdf",
        "dublicate.pdf",
        "application/pdf",
        "New Title"
      )

      assert FileStorage.exists?("dublicate.pdf")

      assert File.exists?(
               "./file_storage/E32843258ACB50D059D0/24866FBF6EBC275A48B0/9574A0799EF0263055AC/6343/dublicate.pdf"
             )

      file_item = FileStorage.get_file_by_name!("dublicate.pdf")

      assert file_item.name == "dublicate.pdf"
      assert file_item.type == "application/pdf"
      assert file_item.title == "New Title"

      File.rm("dublicate.pdf")
    end
  end

  describe "exists?/1" do
    test "returns true if file exists" do
      File.mkdir_p(
        "file_storage/66BDAB382A1B0B067304/0380AE4D395D729A885F/5CF09F2B0ABD552AA123/CF60"
      )

      File.touch(
        "file_storage/66BDAB382A1B0B067304/0380AE4D395D729A885F/5CF09F2B0ABD552AA123/CF60/filename.txt"
      )

      assert FileStorage.exists?("filename.txt")
    end

    test "returns false if the file does not exist" do
      refute FileStorage.exists?("no_filename.txt")
    end
  end
end
