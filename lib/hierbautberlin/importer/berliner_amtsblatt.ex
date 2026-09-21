defmodule Hierbautberlin.Importer.BerlinerAmtsblatt do
  import SweetXml
  import Ecto.Query, warn: false
  require Logger

  alias Hierbautberlin.FileStorage
  alias Hierbautberlin.GeoData
  alias Hierbautberlin.GeoData.{NewsItem, Source}
  alias Hierbautberlin.Repo
  alias Hierbautberlin.Services.UnicodeHelper

  @months [
    "Januar",
    "Februar",
    "März",
    "April",
    "Mai",
    "Juni",
    "Juli",
    "August",
    "September",
    "Oktober",
    "November",
    "Dezember"
  ]

  def import(
        http_connection \\ Hierbautberlin.HTTPClient,
        downloader \\ Hierbautberlin.HTTPClient
      ) do
    {:ok, do_import_folder() ++ do_import_webpage(http_connection, downloader)}
  rescue
    error ->
      Bugsnag.report(error)
      {:error, error}
  end

  def import_folder() do
    {:ok, do_import_folder()}
  rescue
    error ->
      Bugsnag.report(error)
      {:error, error}
  end

  def import_webpage(
        http_connection \\ Hierbautberlin.HTTPClient,
        downloader \\ Hierbautberlin.HTTPClient
      ) do
    news_items = do_import_webpage(http_connection, downloader)
    warn_if_outdated()
    {:ok, news_items}
  rescue
    error ->
      Bugsnag.report(error)
      {:error, error}
  end

  # berlin.de only lists the last six issues, older ones are deleted. A new issue
  # appears every week, so no new issue for three weeks means the import is
  # broken (e.g. the page layout changed) and issues will be lost soon.
  @outdated_after_days 21

  def warn_if_outdated(now \\ DateTime.utc_now()) do
    newest =
      Repo.one(
        from item in NewsItem,
          join: source in Source,
          on: source.id == item.source_id,
          where: source.short_name == "BERLIN_AMTSBLATT",
          select: max(item.published_at)
      )

    if newest && DateTime.diff(now, newest, :day) > @outdated_after_days do
      message = "The newest Amtsblatt issue is from #{Date.to_iso8601(DateTime.to_date(newest))}"
      Logger.warning(message)
      Bugsnag.report(%RuntimeError{message: message}, severity: "warning")
      :outdated
    else
      :ok
    end
  end

  def do_import_folder() do
    import_path = Path.join(Application.get_env(:hierbautberlin, :import_path), "amtsblatt")

    import_path
    |> File.ls!()
    |> Enum.map(fn file ->
      file_name = Path.join(import_path, file)
      news_items = import_and_store(file_name, get_storage_name(file_name))
      File.rm(file_name)
      news_items
    end)
    |> List.flatten()
  end

  def do_import_webpage(http_connection, downloader) do
    # The page lists the latest issues, import all we don't have yet (oldest first)
    http_connection
    |> get_amtsblatt_urls()
    |> Enum.reverse()
    |> Enum.reject(&FileStorage.exists?(get_storage_name(&1)))
    |> Enum.flat_map(fn pdf_url ->
      file = download_pdf(downloader, pdf_url)

      try do
        import_and_store(file, get_storage_name(pdf_url))
      after
        File.rm(file)
      end
    end)
  end

  # A stored PDF counts as imported, so it is only stored after its news items
  # were imported. Otherwise a failed import (or download) is never retried.
  defp import_and_store(file, storage_name) do
    news_items = import_amtsblatt(file)
    store_pdf(storage_name, file)
    news_items
  end

  def get_storage_name(pdf_url) do
    "amtsblatt/#{Path.basename(pdf_url)}"
  end

  def store_pdf(storage_name, file) do
    max_pages = get_number_of_pages(file)

    last_page =
      file
      |> get_structure()
      |> get_last_page(max_pages)

    target_file =
      Path.join(
        Path.dirname(file),
        "limited_#{Path.basename(file)}"
      )

    System.cmd("qpdf", ["--empty", "--pages", file, "1-#{last_page}", "--", target_file])
    FileStorage.store_file(storage_name, target_file, "application/pdf", title_for_file(file))
    File.rm(target_file)
  end

  def title_for_file(file) do
    capture =
      Regex.named_captures(
        ~r/abl_(?<year>\d{4})_(?<number>\d*).*/,
        file
      )

    volume = String.to_integer(capture["year"]) - 1950

    "Amtsblatt für Berlin, #{volume}. Jahrgang Nr. #{capture["number"]}"
  end

  def get_amtsblatt_urls(http_connection) do
    url = "https://www.berlin.de/landesverwaltungsamt/logistikservice/amtsblatt-fuer-berlin/"

    response =
      http_connection.get!(
        url,
        ["User-Agent": "hierbautberlin.de"],
        timeout: 60_000,
        recv_timeout: 60_000
      )

    if response.status_code != 200 do
      []
    else
      find_download_urls(response.body)
    end
  end

  @doc """
  Returns the urls of all Amtsblatt PDFs linked on the page, newest first.
  """
  def find_download_urls(html) do
    {:ok, document} = Floki.parse_document(html)

    document
    # ".download-btn a" is the layout until 2024
    |> Floki.find(".download-btn a, a.link--download")
    |> Floki.attribute("href")
    |> Enum.map(fn href -> href |> URI.parse() |> Map.put(:query, nil) |> URI.to_string() end)
    |> Enum.filter(&String.ends_with?(&1, ".pdf"))
    |> Enum.map(&(URI.merge("https://www.berlin.de", &1) |> URI.to_string()))
    |> Enum.uniq()
  end

  def download_pdf(downloader, url) do
    dir = System.tmp_dir()
    filename = Path.join(dir, Path.basename(url))
    file = File.open!(filename, [:write])
    downloader.get(url, file)
    File.close(file)
    filename
  end

  def import_amtsblatt(file, max_page \\ nil) do
    {:ok, source} =
      GeoData.upsert_source(%{
        short_name: "BERLIN_AMTSBLATT",
        name: "Amtsblatt für Berlin",
        url: "https://www.berlin.de/landesverwaltungsamt/logistikservice/amtsblatt-fuer-berlin/",
        copyright: "Landesverwaltungsamt Berlin"
      })

    file
    |> extract_items(max_page)
    |> Enum.map(fn item ->
      GeoData.upsert_news_item!(
        %{
          external_id: item.url,
          title: truncate(item.title, 250),
          url: item.url,
          content: item.description,
          published_at: item.published_at,
          source_id: source.id
        },
        item.full_text,
        [item.section]
      )
    end)
  end

  @doc """
  Extracts the news items of an Amtsblatt PDF without storing anything.
  """
  def extract_items(file, max_page \\ nil) do
    # Some PDFs are rather special and don't follow the structure.
    # Those need to be ignored.
    case get_structure(file) do
      [%{title: "Inhalt"} | _] = structure ->
        last_page = max_page || get_last_page(structure, get_number_of_pages(file))
        extract_items_with_structure(file, structure, last_page)

      _ ->
        []
    end
  end

  @doc """
  Extracts the news items along the given structure (maps with `:title` and
  `:page_number` in PDF order, returned as `:structure_item`). Used for the
  stored PDFs, which have no outline anymore.
  """
  def extract_items_with_structure(file, structure, last_page) do
    pages = extract_pages(file, last_page)
    publish_date = get_date_from_page(List.first(pages))

    pages
    |> extract_news(structure)
    |> Enum.map(fn item ->
      # A keyword list keeps the parameter order stable, the url is used as external_id
      query = [
        page: item.item.page_number,
        title: String.slice(item.title, 0, 100)
      ]

      %{
        url: "/view_pdf/amtsblatt/#{Path.basename(file)}?#{URI.encode_query(query)}",
        title: item.title,
        description: item.description,
        full_text: item.full_text,
        section: item.item.title,
        page_number: item.item.page_number,
        structure_item: item.item,
        published_at: DateTime.new!(publish_date, ~T[13:26:08.003], "Etc/UTC")
      }
    end)
  end

  def get_number_of_pages(file) do
    {pages, 0} = System.cmd("qpdf", ["--show-npages", file])

    pages
    |> String.trim()
    |> String.to_integer()
  end

  def get_structure(file) do
    {structure, 0} = System.cmd("dumppdf.py", ["--extract-toc", file])

    # PDFs without an outline (e.g. the stored, shortened ones) return nothing
    if String.contains?(structure, "<outlines"), do: parse_structure(structure), else: []
  end

  defp parse_structure(structure) do
    structure
    |> xpath(
      ~x"//outlines/outline"l,
      level: ~x"@level"s |> transform_by(&to_integer/1),
      title: ~x"@title"s |> transform_by(&clean_structure_title/1),
      page_number: ~x"./pageno/text()"s |> transform_by(&to_integer/1)
    )
  end

  defp to_integer(nil) do
    nil
  end

  defp to_integer("") do
    nil
  end

  defp to_integer(string) do
    String.to_integer(string)
  end

  defp clean_structure_title(string) do
    if String.match?(string, ~r/b'(.*)'/) do
      String.replace(string, ~r/b'(.*)'/, "\\1")
    else
      string
    end
    |> String.trim()
  end

  def get_last_page(structure, number_of_pages) do
    position =
      Enum.find_index(structure, fn item ->
        item.title == "Stellenausschreibungen" ||
          item.title == "Gerichte" ||
          item.title == "Nicht amtlicher Teil"
      end)

    line = position != nil && Enum.at(structure, position + 1)

    # Some outlines have no page numbers at all (dumppdf.py cannot resolve the
    # destinations), then we keep all pages
    if line && line.page_number do
      line.page_number - 1
    else
      number_of_pages
    end
  end

  def extract_pages(file, last_page) do
    Enum.map(1..last_page, fn page ->
      extract_page(file, page)
    end)
  end

  def extract_page(file, page) do
    lines =
      file
      |> read_from_file(page)
      |> String.trim()
      |> String.split("\n")

    first_line = first_line_after_header(lines)
    last_line = last_line_before_footer(lines)

    Enum.slice(lines, first_line, last_line - first_line)
    |> Enum.join("\n")
    |> String.trim()
  end

  defp first_line_after_header(lines) do
    first_line = List.first(lines)

    Enum.find_index(lines, fn line ->
      line != "" && line != first_line
    end)
  end

  defp last_line_before_footer(lines) do
    line_length = length(lines)

    if String.match?(
         lines |> Enum.at(line_length - 1) |> String.trim(),
         ~r/^ABl\. Nr\. .* \d{4}$/
       ) do
      line_length - 1
    else
      line_length
    end
  end

  defp read_from_file(file, page) do
    dir = System.tmp_dir!()
    tmp_file = Path.join(dir, Ecto.UUID.generate() <> ".txt")

    {_, 0} =
      System.cmd("pdftotext", [
        "-layout",
        "-f",
        Integer.to_string(page),
        "-l",
        Integer.to_string(page),
        file,
        tmp_file
      ])

    {:ok, text} = File.read(tmp_file)
    File.rm(tmp_file)

    text
  end

  def get_date_from_filename(filename) do
    filename
    |> extract_page(1)
    |> get_date_from_page()
  end

  def get_date_from_page(page) do
    capture =
      Regex.named_captures(
        ~r/Ausgegeben zu Berlin am (?<day>\d{1,2}). (?<month>\w*) (?<year>\d{4})/u,
        page
      )

    Date.new!(
      String.to_integer(capture["year"]),
      month_to_number(capture["month"]),
      String.to_integer(capture["day"])
    )
  end

  defp month_to_number(month) do
    Enum.find_index(@months, fn item -> item == month end) + 1
  end

  def extract_news(pages, structure) do
    pages = Enum.map(pages, &String.split(&1, "\n"))
    filtered_structure = Enum.filter(structure, &(&1.page_number != nil))

    result =
      filtered_structure
      |> Stream.with_index()
      |> Enum.reduce(%{last_page: 0, last_line: 0, items: []}, fn {item, index}, acc ->
        next_item = Enum.at(filtered_structure, index + 1)

        if item.page_number <= length(pages) && should_import_topic?(item) do
          extract_news_item(item, next_item, pages, acc)
        else
          acc
        end
      end)

    result.items
  end

  defp extract_news_item(item, next_item, pages, acc) do
    page = Enum.at(pages, item.page_number - 1)
    next_item = if next_item && next_item.page_number > length(pages), do: nil, else: next_item

    {_, content_start_line} =
      if item.page_number == acc.last_page do
        find_section(page, item.title, acc.last_line)
      else
        find_section(page, item.title)
      end

    if content_start_line do
      {end_line, text} =
        extract_text_for_item(item, next_item, page, pages, content_start_line + 1)

      text = trim_and_join_lines(text)

      news = %{
        full_text: text,
        item: item,
        title: extract_title(text),
        description: extract_description(text)
      }

      %{
        last_page: if(next_item, do: next_item.page_number, else: item.page_number),
        last_line: end_line,
        items: acc.items ++ [news]
      }
    else
      acc
    end
  end

  @skipped_sections ~r/\wkammer (zu )?Berlin|Apothekerversorgung Berlin|Lette-Verein|Versorgungswerk|\WInnung\W/

  defp should_import_topic?(item) do
    !String.match?(item.title, @skipped_sections)
  end

  @doc """
  Cuts the text at the heading of a section that is not imported (chambers,
  guilds, ...). Without the outline those sections end up in the text of the
  item before them.
  """
  def cut_at_skipped_section(text) do
    lines = String.split(text, "\n")

    heading =
      lines
      |> Enum.with_index()
      |> Enum.find(fn {line, index} ->
        index > 0 and String.length(line) <= 60 and String.match?(" " <> line, @skipped_sections) and
          String.trim(Enum.at(lines, index + 1) || "") == ""
      end)

    case heading do
      {_line, index} -> lines |> Enum.take(index) |> Enum.join("\n") |> String.trim()
      nil -> text
    end
  end

  def extract_text_for_item(item, next_item, page, pages, start_line)

  # If there are no next items, grab the rest of the pages
  def extract_text_for_item(item, nil, page, pages, start_line) do
    end_line = length(page)

    text =
      (Enum.slice(page, start_line, end_line - start_line) ++
         Enum.slice(
           pages,
           item.page_number,
           length(pages) - item.page_number
         ))
      |> List.flatten()

    {end_line, text}
  end

  # If the next item is on the same page, grab the text till it's start
  def extract_text_for_item(
        %{page_number: page_number},
        %{page_number: next_page_number} = next_item,
        page,
        _pages,
        start_line
      )
      when page_number == next_page_number do
    {end_line, _} = find_section(page, next_item.title, start_line + 1)

    if end_line do
      {end_line, Enum.slice(page, start_line, end_line - start_line)}
    else
      page_length = length(page)
      {page_length, Enum.slice(page, start_line, page_length - start_line)}
    end
  end

  # Find the next item and grab all text till it's start
  def extract_text_for_item(item, next_item, page, pages, start_line) do
    next_item_page =
      if next_item do
        Enum.at(pages, next_item.page_number - 1)
      else
        nil
      end

    text = Enum.slice(page, start_line, length(page) - start_line)

    {next_title_start, _} = find_section(next_item_page, next_item.title)

    text =
      (text ++
         Enum.slice(
           pages,
           item.page_number,
           next_item.page_number - item.page_number - 1
         ))
      |> List.flatten()

    text =
      if next_title_start == nil do
        text
      else
        text ++ Enum.slice(next_item_page, 0, next_title_start)
      end

    {next_title_start, text}
  end

  def trim_and_join_lines(lines) do
    lines
    |> Enum.map(&String.trim(&1))
    |> Enum.reduce("", &join_line(&2, &1))
    |> String.trim()
  end

  defp join_line(acc, line) do
    cond do
      not String.ends_with?(acc, "-") ->
        acc <> "\n" <> line

      # If the 2 characters before the - are lower case letters and
      # the 2 characters after the - are lower case letters, join the line
      # and remove the "-", otherwise just add the line
      hyphenated_word?(acc, line) ->
        String.slice(acc, 0, String.length(acc) - 1) <> line

      true ->
        acc <> line
    end
  end

  defp hyphenated_word?(acc, line) do
    UnicodeHelper.lower_case_letter?(String.at(acc, -3)) &&
      UnicodeHelper.lower_case_letter?(String.at(acc, -2)) &&
      UnicodeHelper.lower_case_letter?(String.at(line, 0)) &&
      UnicodeHelper.lower_case_letter?(String.at(line, 1))
  end

  def find_section(page, title, start \\ 0) do
    {title, truncated?} = title |> clean_title() |> split_truncated()

    %{start: line_start, end: line_end} =
      page
      |> Stream.with_index()
      |> Enum.reduce_while(
        %{
          start: 0,
          previous_lines: ""
        },
        fn {line, index},
           %{
             start: line_start,
             previous_lines: previous_lines
           } ->
          line_with_previous_lines = clean_title(previous_lines <> " " <> line)
          line = clean_title(line)

          cond do
            index < start ->
              {:cont,
               %{
                 start: index,
                 end: nil,
                 previous_lines: ""
               }}

            title == line ->
              {:halt,
               %{
                 start: index,
                 end: index
               }}

            complete_title?(line_with_previous_lines, title, truncated?) ->
              {:halt,
               %{
                 start: line_start,
                 end: index
               }}

            String.starts_with?(title, line_with_previous_lines) ->
              {:cont,
               %{
                 start: line_start,
                 end: nil,
                 previous_lines: line_with_previous_lines
               }}

            true ->
              {:cont,
               %{
                 start: index,
                 end: nil,
                 previous_lines: line
               }}
          end
        end
      )

    if line_start && line_end do
      {line_start, line_end}
    else
      {nil, nil}
    end
  end

  # stored news item titles are cut after 250 characters
  defp split_truncated(title) do
    if String.ends_with?(title, "..."),
      do: {String.slice(title, 0..-4//1), true},
      else: {title, false}
  end

  defp complete_title?(text, title, truncated?) do
    text == title or (truncated? and String.starts_with?(text, title))
  end

  # Titles are compared without whitespace, the PDF text has line breaks and
  # different spacing ("(IfSG) -Isolation" vs. "(IfSG) - Isolation")
  defp clean_title(title) do
    String.replace(title, ~r/\s+/u, "")
  end

  defp extract_title(text) do
    capture =
      Regex.named_captures(
        ~r/\A(?<title>.*?)\n\s*\n/s,
        text
      )

    if capture["title"] do
      capture["title"]
      |> String.replace("\n", " ")
      |> String.replace("  ", " ")
    else
      # Sometimes the title is not separated by two empty lines, then
      # we take the first line as title.
      capture =
        Regex.named_captures(
          ~r/(?<title>.*)/,
          text
        )

      capture["title"]
    end
  end

  defp extract_description(text) do
    capture =
      Regex.named_captures(
        ~r/.*?(\n\s*\n)(?<description>.*)/s,
        text
      )

    if capture["description"] do
      capture["description"]
      |> String.split(~r/[\.:]\n/)
      |> List.first()
      |> String.trim()
    else
      ""
    end
  end

  defp truncate(text, length) do
    if String.length(text) > length do
      String.slice(text, 0, length - 3) <> "..."
    else
      text
    end
  end
end
