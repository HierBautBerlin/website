# Evaluates the address matching (AnalyzeText) against the gold set.
#
#     DATABASE_PORT=5434 DATABASE_NAME=hierbautberlin_osm mix run bench/matching/eval.exs [--errors] [--write-predictions]
#
# Needs a database with imported streets and places (bin/import_geo_objects.sh).
# texts.json is collected by collect_texts.exs, expected.json is maintained by hand:
#
#     {"12": {"streets": ["Karl-Marx-Allee|Friedrichshain-Kreuzberg"],
#             "street_numbers": ["Karl-Marx-Allee 12|Friedrichshain-Kreuzberg"],
#             "places": ["Volkspark Friedrichshain|Friedrichshain-Kreuzberg"]}}
Logger.configure(level: :warning)

alias Hierbautberlin.GeoData.AnalyzeText
alias Hierbautberlin.Repo
alias Hierbautberlin.Services.Berlin

args = System.argv()
data_dir = "test/support/data/matching"

texts = Path.join(data_dir, "texts.json") |> File.read!() |> Jason.decode!()

expected =
  case File.read(Path.join(data_dir, "expected.json")) do
    {:ok, json} -> Jason.decode!(json)
    _ -> %{}
  end

# AnalyzeText is not started in dev (no importers there)
unless Process.whereis(AnalyzeText) do
  {:ok, _} = AnalyzeText.start_link(name: AnalyzeText)
  # the index is built asynchronously after start
  AnalyzeText.reload()
end

to_keys = fn result ->
  street_numbers = Repo.preload(result.street_numbers, :geo_street)

  %{
    "streets" => Enum.map(result.streets, &"#{&1.name}|#{&1.district}"),
    "street_numbers" =>
      Enum.map(street_numbers, &"#{&1.geo_street.name} #{&1.number}|#{&1.geo_street.district}"),
    "places" => Enum.map(result.places, &"#{&1.name}|#{&1.district}")
  }
end

districts_for = fn text ->
  text["context"] |> List.wrap() |> Enum.flat_map(&Berlin.find_districts/1) |> Enum.uniq()
end

{micro, predictions} =
  :timer.tc(fn ->
    Map.new(texts, fn text ->
      result = AnalyzeText.analyze_text(text["text"], %{districts: districts_for.(text)})
      {to_string(text["id"]), to_keys.(result)}
    end)
  end)

if "--write-predictions" in args do
  File.write!(
    Path.join(data_dir, "predictions.json"),
    Jason.encode_to_iodata!(predictions, pretty: true)
  )
end

annotated_ids = Map.keys(expected)

# A found street number also counts as its street in the lenient score
lenient = fn keys ->
  numbers_as_streets =
    Enum.map(keys["street_numbers"] || [], fn key ->
      [name_number, district] = String.split(key, "|")
      name = String.replace(name_number, ~r/\s+\S+$/, "")
      "#{name}|#{district}"
    end)

  Enum.uniq((keys["streets"] || []) ++ numbers_as_streets)
end

score = fn get ->
  Enum.reduce(annotated_ids, %{tp: 0, fp: 0, fn: 0, errors: []}, fn id, acc ->
    predicted = MapSet.new(get.(predictions[id] || %{}))
    wanted = MapSet.new(get.(expected[id]))
    false_positives = MapSet.difference(predicted, wanted) |> MapSet.to_list()
    false_negatives = MapSet.difference(wanted, predicted) |> MapSet.to_list()

    errors =
      if false_positives == [] and false_negatives == [],
        do: acc.errors,
        else: [{id, false_positives, false_negatives} | acc.errors]

    %{
      tp: acc.tp + MapSet.size(MapSet.intersection(predicted, wanted)),
      fp: acc.fp + length(false_positives),
      fn: acc.fn + length(false_negatives),
      errors: errors
    }
  end)
end

metrics = fn %{tp: tp, fp: fp, fn: fn_count} ->
  precision = if tp + fp == 0, do: 1.0, else: tp / (tp + fp)
  recall = if tp + fn_count == 0, do: 1.0, else: tp / (tp + fn_count)
  f1 = if precision + recall == 0, do: 0.0, else: 2 * precision * recall / (precision + recall)
  {Float.round(precision, 3), Float.round(recall, 3), Float.round(f1, 3)}
end

categories = [
  {"streets", &(&1["streets"] || [])},
  {"street_numbers", &(&1["street_numbers"] || [])},
  {"places", &(&1["places"] || [])},
  {"streets (lenient)", lenient}
]

IO.puts(
  "#{length(texts)} texts, #{length(annotated_ids)} annotated, " <>
    "#{Float.round(micro / 1_000_000, 1)}s (#{Float.round(micro / 1000 / length(texts), 0)}ms per text)\n"
)

IO.puts("| category | precision | recall | F1 | TP | FP | FN |")
IO.puts("|---|---|---|---|---|---|---|")

results =
  for {name, get} <- categories do
    result = score.(get)
    {precision, recall, f1} = metrics.(result)
    IO.puts("| #{name} | #{precision} | #{recall} | #{f1} | #{result.tp} | #{result.fp} | #{result.fn} |")
    {name, result}
  end

if "--errors" in args do
  titles = Map.new(texts, &{to_string(&1["id"]), &1["title"]})

  for {name, result} <- results, name != "streets (lenient)" do
    IO.puts("\n## #{name}")

    for {id, false_positives, false_negatives} <- Enum.sort_by(result.errors, &String.to_integer(elem(&1, 0))) do
      IO.puts("#{id} #{String.slice(titles[id] || "", 0, 70)}")
      if false_positives != [], do: IO.puts("   FP: #{Enum.join(false_positives, "; ")}")
      if false_negatives != [], do: IO.puts("   FN: #{Enum.join(false_negatives, "; ")}")
    end
  end
end
