# Collects real texts for the address matching gold set.
#
#     mix run --no-start bench/matching/collect_texts.exs [press_pages]
#
# Writes test/support/data/matching/texts.json. The expected results are
# maintained by hand in test/support/data/matching/expected.json.
{:ok, _} = Application.ensure_all_started(:req)
{:ok, _} = Application.ensure_all_started(:timex)

alias Hierbautberlin.Importer.{BerlinerAmtsblatt, BerlinPresse}

defmodule SlowHTTPClient do
  # berlin.de answers with redirect loops when requests come in too fast
  def get!(url, headers, opts) do
    Process.sleep(700)
    Hierbautberlin.HTTPClient.get!(url, headers, opts)
  end
end

press_pages = System.argv() |> List.first("6") |> String.to_integer()

press =
  for page <- 1..press_pages, entry <- BerlinPresse.fetch_entries(SlowHTTPClient, page) do

    %{
      source: "presse",
      title: entry.title,
      url: entry.url,
      context: entry.districts,
      text: entry.full_text
    }
  end

IO.puts("#{length(press)} press releases")

dir = Path.join(System.tmp_dir!(), "matching_amtsblatt")
File.mkdir_p!(dir)

amtsblatt =
  for url <- BerlinerAmtsblatt.get_amtsblatt_urls(SlowHTTPClient),
      file = Path.join(dir, Path.basename(url)),
      :ok = File.exists?(file) && :ok || (File.write!(file, Req.get!(url, decode_body: false).body) && :ok),
      item <- BerlinerAmtsblatt.extract_items(file) do
    %{
      source: "amtsblatt",
      title: item.title,
      url: "#{Path.basename(file)} #{item.url}",
      context: [item.section],
      text: item.full_text
    }
  end

IO.puts("#{length(amtsblatt)} Amtsblatt items")

texts =
  (press ++ amtsblatt)
  |> Enum.uniq_by(& &1.url)
  |> Enum.with_index(1)
  |> Enum.map(fn {text, index} -> Map.put(text, :id, index) end)

File.write!(
  "test/support/data/matching/texts.json",
  Jason.encode_to_iodata!(texts, pretty: true)
)
