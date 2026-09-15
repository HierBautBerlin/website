# Refetches the article text of press releases in texts.json that have no body
# (berlin.de sometimes answers with redirect loops when throttling).
#
#     mix run --no-start bench/matching/refetch_missing.exs
{:ok, _} = Application.ensure_all_started(:req)

path = "test/support/data/matching/texts.json"
texts = path |> File.read!() |> Jason.decode!()

texts =
  Enum.map(texts, fn text ->
    lines = String.split(text["text"], "\n", parts: 3)

    if text["source"] == "presse" and length(lines) < 3 || (text["source"] == "presse" and String.trim(List.last(lines)) == "") do
      Process.sleep(3_000)

      body =
        try do
          response = Hierbautberlin.HTTPClient.get!(text["url"], ["User-Agent": "hierbautberlin.de"])
          {:ok, document} = Floki.parse_document(response.body)
          document |> Floki.find(".article[role='main']") |> Floki.text()
        rescue
          error ->
            IO.puts("failed #{text["url"]}: #{Exception.message(error)}")
            ""
        end

      [title, content | _] = lines ++ ["", ""]
      Map.put(text, "text", Enum.join([title, content, body], "\n"))
    else
      text
    end
  end)

File.write!(path, Jason.encode_to_iodata!(texts, pretty: true))
