defmodule Hierbautberlin.Importer.BerlinerAmtsblatt do
  import SweetXml

  alias Hierbautberlin.FileStorage
  alias Hierbautberlin.GeoData
  alias Phoenix.HTML.SimplifiedHelpers.Truncate

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

  def import(http_connection \\ HTTPoison, downloader \\ Downstream) do
    {:ok, import_folder() ++ import_webpage(http_connection, downloader)}
  rescue
    error ->
      Bugsnag.report(error)
      {:error, error}
  end

  def import_folder() do
    import_path = Path.join(Application.get_env(:hierbautberlin, :import_path), "amtsblatt")

    import_path
    |> File.ls!()
    |> Enum.map(fn file ->
      file_name = Path.join(import_path, file)

      file_name
      |> get_storage_name()
      |> store_pdf(file_name)

      news_items = import_amtsblatt(file_name)
      File.rm(file_name)
      news_items
    end)
    |> List.flatten()
  end

  def import_webpage(http_connection, downloader) do
    pdf_url = get_latest_amtsblatt(http_connection)

    if pdf_url && !FileStorage.exists?(get_storage_name(pdf_url)) do
      file = download_pdf(downloader, pdf_url)

      pdf_url
      |> get_storage_name()
      |> store_pdf(file)

      news_items = import_amtsblatt(file)
      File.rm(file)
      news_items
    else
      []
    end
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

  def get_latest_amtsblatt(http_connection) do
    url = "https://www.berlin.de/landesverwaltungsamt/logistikservice/amtsblatt-fuer-berlin/"

    response =
      http_connection.get!(
        url,
        ["User-Agent": "hierbautberlin.de"],
        timeout: 60_000,
        recv_timeout: 60_000
      )

    if response.status_code != 200 do
      nil
    else
      find_download_url(response.body)
    end
  end

  defp find_download_url(text) do
    {:ok, document} = Floki.parse_document(text)

    url =
      document
      |> Floki.find(".download-btn a")
      |> Floki.attribute("href")
      |> List.first()
      |> Floki.text()

    if String.length(url) > 0 do
      "https://www.berlin.de" <> url
    else
      nil
    end
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

    number_of_pages = get_number_of_pages(file)
    structure = get_structure(file)
    first_item = List.first(structure)

    # Some PDFs are rather special and don't follow the structure.
    # Those need to be ignored.
    if first_item.title == "Inhalt" do
      last_page = max_page || get_last_page(structure, number_of_pages)
      pages = extract_pages(file, last_page)
      publish_date = get_date_from_page(List.first(pages))

      items = extract_news(pages, structure)

      Enum.map(items, fn item ->
        query = %{
          page: item.item.page_number,
          title: String.slice(item.title, 0, 100)
        }

        url = "/view_pdf/amtsblatt/#{Path.basename(file)}?#{URI.encode_query(query)}"

        GeoData.create_news_item!(
          %{
            external_id: url,
            title: Truncate.truncate(item.title, length: 250),
            url: url,
            content: item.description,
            published_at: DateTime.new!(publish_date, ~T[13:26:08.003], "Etc/UTC"),
            source_id: source.id
          },
          item.full_text,
          districts: [item.item.title]
        )
      end)
    end
  end

  def get_number_of_pages(file) do
    {pages, 0} = System.cmd("qpdf", ["--show-npages", file])

    pages
    |> String.trim()
    |> String.to_integer()
  end

  def get_structure(file) do
    {structure, 0} = System.cmd("dumppdf.py", ["--extract-toc", file])

    structure
    |> xpath(
      ~x"//outlines/outline"l,
      level: ~x"@level"s |> transform_by(&to_integer/1),
      title: ~x"@title"s |> transform_by(&clean_title/1),
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

  defp clean_title(string) do
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

    if line do
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
        ~r/Ausgegeben zu Berlin am (?<day>\d{1,2}). (?<month>\w*) (?<year>\d{4})/,
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
    pages =
      Enum.map(pages, fn page ->
        String.split(page, "\n")
      end)

    number_of_pages = length(pages)

    filtered_structure =
      structure
      |> Enum.filter(fn item ->
        item.page_number != nil
      end)

    result =
      filtered_structure
      |> Stream.with_index()
      |> Enum.reduce(%{last_page: 0, last_line: 0, items: []}, fn {item, index}, acc ->
        if item.page_number <= number_of_pages do
          page = Enum.at(pages, item.page_number - 1)
          next_item = Enum.at(filtered_structure, index + 1)

          next_item =
            if next_item && next_item.page_number > number_of_pages do
              nil
            else
              next_item
            end

          start_line =
            if item.page_number == acc.last_page do
              find_title(page, item.title, acc.last_line) + 1
            else
              find_title(page, item.title) + 1
            end

          {end_line, text} = extract_text_for_item(item, next_item, page, pages, start_line)
          text = join_and_trim_lines(text)

          %{
            last_page: if(next_item, do: next_item.page_number, else: item.page_number),
            last_line: end_line,
            items:
              acc.items ++
                [
                  %{
                    full_text: text,
                    item: item,
                    title: extract_title(text),
                    description: extract_description(text)
                  }
                ]
          }
        else
          acc
        end
      end)

    result.items
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
    end_line = find_title(page, next_item.title, start_line + 1)
    {end_line, Enum.slice(page, start_line, end_line - start_line)}
  end

  # Find the next item and grab all text till it's start
  def extract_text_for_item(item, next_item, page, pages, start_line) do
    next_item_page =
      if next_item do
        Enum.at(pages, next_item.page_number - 1)
      else
        nil
      end

    end_line = length(page)
    text = Enum.slice(page, start_line, end_line - start_line)
    end_line = find_title(next_item_page, next_item.title) || length(next_item_page)

    text =
      (text ++
         Enum.slice(
           pages,
           item.page_number,
           next_item.page_number - item.page_number - 1
         ))
      |> List.flatten()

    text =
      if end_line == 0 do
        text
      else
        text ++ Enum.slice(next_item_page, 0, end_line - 1)
      end

    {end_line, text}
  end

  def join_and_trim_lines(lines) do
    lines
    |> Enum.map(&String.trim(&1))
    |> Enum.join("\n")
    |> String.trim()
  end

  defp find_title(page, title, start \\ 0) do
    page
    |> Stream.with_index()
    |> Enum.find_index(fn {line, index} ->
      previous_line = Enum.at(page, index - 1) || ""
      with_previous_line = String.trim(previous_line) <> " " <> String.trim(line || "")

      index >= start &&
        (line == title || with_previous_line == title)
    end)
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
      |> String.split(".\n")
      |> List.first()
      |> String.trim()
    else
      ""
    end
  end
end
