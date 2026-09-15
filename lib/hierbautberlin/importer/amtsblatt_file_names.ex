defmodule Hierbautberlin.Importer.AmtsblattFileNames do
  @moduledoc """
  Repairs the Amtsblatt issues imported between April and June 2023. berlin.de
  added `?ts=…` to the PDF links then and the importer kept it in the file name,
  so the PDF links of those news items don't work
  (`/view_pdf/amtsblatt/abl_2023_29_…_online.pdf?ts=1688105763?page=95&title=…`).

  The importer strips the query since then. This moves the stored files, renames
  the file entries and fixes the links. Files and news items that also exist
  without the timestamp (issues imported twice) are deleted. Running it again
  changes nothing.
  """
  import Ecto.Query, warn: false
  require Logger

  alias Hierbautberlin.FileStorage
  alias Hierbautberlin.FileStorage.FileItem
  alias Hierbautberlin.GeoData.NewsItem
  alias Hierbautberlin.Repo

  @timestamp ~r/\?ts=\d+/

  def run do
    files = Enum.map(files_with_timestamp(), &repair_file/1)
    news = Repo.transaction(fn -> Enum.map(news_items_with_timestamp(), &repair_news_item/1) end)

    {:ok, news} = news

    stats = %{
      files_moved: Enum.count(files, &(&1 == :moved)),
      files_already_existing: Enum.count(files, &(&1 == :exists)),
      files_missing: Enum.count(files, &(&1 == :missing)),
      news_items_fixed: Enum.count(news, &(&1 == :fixed)),
      news_items_deleted: Enum.count(news, &(&1 == :deleted))
    }

    Logger.info("Repaired Amtsblatt file names: #{inspect(stats)}")
    stats
  end

  defp files_with_timestamp do
    Repo.all(from file in FileItem, where: like(file.name, "amtsblatt/%?ts=%"))
  end

  defp news_items_with_timestamp do
    Repo.all(from item in NewsItem, where: like(item.external_id, "/view_pdf/amtsblatt/%?ts=%"))
  end

  defp repair_file(%FileItem{name: name} = file) do
    new_name = String.replace(name, @timestamp, "")

    cond do
      # the issue was imported twice, the file without timestamp is used
      FileStorage.get_file_by_name(new_name) ->
        File.rm(FileStorage.path_for_file(name))
        {:ok, _} = FileStorage.delete_file(file)
        :exists

      File.exists?(FileStorage.path_for_file(name)) ->
        target = FileStorage.path_for_file(new_name)
        File.mkdir_p!(Path.dirname(target))
        File.rename!(FileStorage.path_for_file(name), target)
        {:ok, _} = FileStorage.update_file(file, %{name: new_name})
        :moved

      true ->
        Logger.warning("Amtsblatt file #{name} is not in the file storage")
        {:ok, _} = FileStorage.update_file(file, %{name: new_name})
        :missing
    end
  end

  # "…online.pdf?ts=1688105763?page=95&title=…" -> "…online.pdf?page=95&title=…"
  defp repair_news_item(%NewsItem{external_id: external_id} = news_item) do
    fixed = String.replace(external_id, ~r/\?ts=\d+\?/, "?")

    if Repo.exists?(from item in NewsItem, where: item.external_id == ^fixed) do
      Repo.delete!(news_item)
      :deleted
    else
      news_item
      |> Ecto.Changeset.change(
        external_id: fixed,
        url: String.replace(news_item.url, ~r/\?ts=\d+\?/, "?")
      )
      |> Repo.update!()

      :fixed
    end
  end
end
