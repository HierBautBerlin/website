defmodule Hierbautberlin.FileStorage do
  @moduledoc """
  The FileStorage context.
  """

  import Ecto.Query, warn: false
  alias Hierbautberlin.Repo

  alias Hierbautberlin.FileStorage.FileItem

  @doc """
  Returns the list of files.

  ## Examples

      iex> list_files()
      [%File{}, ...]

  """
  def list_files do
    Repo.all(FileItem)
  end

  @doc """
  Gets a single file.

  Raises `Ecto.NoResultsError` if the File does not exist.

  ## Examples

      iex> get_file!(123)
      %File{}

      iex> get_file!(456)
      ** (Ecto.NoResultsError)

  """
  def get_file!(id), do: Repo.get!(FileItem, id)

  def get_file_by_name!(name) do
    query =
      from file in FileItem,
        where: file.name == ^name

    with {:ok, file} <- Repo.one(query) do
      file
    end
  end

  @doc """
  Creates a file.

  ## Examples

      iex> create_file(%{field: value})
      {:ok, %File{}}

      iex> create_file(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_file(attrs \\ %{}) do
    %FileItem{}
    |> FileItem.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a file.

  ## Examples

      iex> update_file(file, %{field: new_value})
      {:ok, %File{}}

      iex> update_file(file, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_file(%FileItem{} = file, attrs) do
    file
    |> FileItem.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a file.

  ## Examples

      iex> delete_file(file)
      {:ok, %File{}}

      iex> delete_file(file)
      {:error, %Ecto.Changeset{}}

  """
  def delete_file(%FileItem{} = file) do
    Repo.delete(file)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking file changes.

  ## Examples

      iex> change_file(file)
      %Ecto.Changeset{data: %File{}}

  """
  def change_file(%FileItem{} = file, attrs \\ %{}) do
    FileItem.changeset(file, attrs)
  end

  def exists?(filename) do
    filename
    |> path_for_file()
    |> File.exists?()
  end

  def store_file(filename, file, file_type) do
    storage_filename = path_for_file(filename)
    storage_path = Path.dirname(storage_filename)
    File.mkdir_p(storage_path)
    File.cp(file, storage_filename)

    create_file(%{
      name: filename,
      type: file_type
    })
  end

  def path_for_file(filename) do
    base_path = Application.get_env(:hierbautberlin, :file_storage_path)

    path =
      :crypto.mac(:hmac, :sha256, "key", filename)
      |> Base.encode16()
      |> Stream.unfold(&String.split_at(&1, 20))
      |> Enum.take_while(&(&1 != ""))
      |> Path.join()

    Path.join([base_path, path, Path.basename(filename)])
  end
end
