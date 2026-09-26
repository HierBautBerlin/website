defmodule Hierbautberlin.GeoData.AddressMatcher do
  @moduledoc """
  Finds streets, street numbers and places (parks, squares, lakes, landmarks,
  schools, LOR planning areas) in German texts about Berlin.

  The index is built from all streets and places (see `build_index/2`) and kept
  in `:persistent_term`, so matching runs in the calling process and doesn't go
  through a GenServer.

  Matching works on tokens instead of raw strings, which makes it independent of
  case, hyphen/space variants ("Karl-Marx-Allee" / "Karl Marx Allee") and line
  breaks. Every mention is scored:

    * names with a clear street suffix ("…straße", "…allee", …) or several
      words are trusted, generic single-word names ("Weg", "Markt",
      "Innenhof") need more evidence like a house number or a preposition
      ("in der", "am", "Ecke")
    * a street named like an Ortsteil ("Prenzlauer Berg") needs a house number,
      in a text that name is the Ortsteil
    * streets that exist in several districts are resolved with the district
      context of the text (districts given by the importer, district and
      Ortsteil names in the text, other streets found) and house numbers. When
      that leaves a tie between parts of one street that crosses a district
      border (the parts touch), all of them are taken
    * addresses of authorities in legal notices ("…können im Bezirksamt,
      Karl-Marx-Straße 83, 12040 Berlin eingesehen werden") are ignored
  """

  require Logger

  import Ecto.Query, warn: false

  alias Hierbautberlin.GeoData.{GeoPlace, GeoStreet, GeoStreetNumber}
  alias Hierbautberlin.Repo
  alias Hierbautberlin.Services.Berlin

  @index_key {__MODULE__, :index}

  @strong_suffixes ~w(straße allee damm chaussee ufer promenade platz gasse zeile ring brücke
    steig pfad markt tor)

  # Street names that are common words. They are only used when a house number follows.
  @stop_names MapSet.new(~w(weg markt heimat innenhof ausbau übergang schulweg park garten hof
    zentrum mitte rathaus bahnhof allee promenade platz ufer brücke wiese siedlung kreuzung
    brunnen friedhof kirche schule sportplatz spielplatz parkplatz einfahrt ausfahrt durchgang
    zufahrt gewerbehof feldweg fußweg radweg waldweg gartenweg kanalweg landweg seeweg
    tiefgarageneinfahrt verbindungsweg oase galgen jagen seeblick))

  # Words before a name that make it very likely that a location is meant
  @location_cues [
    ["in", "der"],
    ["an", "der"],
    ["auf", "der"],
    ["vor", "der"],
    ["entlang", "der"],
    ["in", "die"],
    ["am"],
    ["im"],
    ["ecke"],
    ["zwischen"],
    ["zur"],
    ["zum"]
  ]

  @enumeration_words ~w(und oder sowie bis)

  @office_words ~w(zimmer raum dienstgebäude dienstsitz dienststelle postfach fachbereich abteilung
    bezirksamt senatsverwaltung geschäftsstelle fraktion landeswahlamt bezirkswahlamt)
  @procedure_words ~w(eingesehen einsehen einsichtnahme widerspruch vorgebracht einzulegen eingelegt
    erhoben stellungnahmen verfügung abgegeben anhörung auslegung ausgelegt fraktion wahlamt
    öffentlichkeitsbeteiligung)

  # Parks and schools are a better location than a street with the same name
  # ("Mauerpark" is the park, not the street next to it). For the other types
  # the street wins: they are often named after each other and the street is
  # what a text with a house number means.
  @place_types_before_streets ~w(Park School)

  # which place wins when several of them have the same name in one district
  @place_type_order %{
    "Park" => 0,
    "Square" => 1,
    "Landmark" => 2,
    "Water" => 3,
    "School" => 4,
    "LOR" => 5
  }

  ## Index

  @doc """
  Loads all streets and places from the database and stores the index.
  """
  def load_index do
    streets = load_streets()

    places =
      Repo.all(
        from p in GeoPlace,
          select: %{id: p.id, name: p.name, district: p.district, type: p.type}
      )

    put_index(build_index(streets, places))
  end

  @doc """
  Loads the street maps for `build_index/2`, including the ids of the streets
  with the same name they touch (`connected`): OSM splits a street that crosses a
  district border into one street per district.
  """
  def load_streets do
    %{rows: rows} =
      Repo.query!("""
      SELECT a.id, array_agg(b.id)
      FROM geo_streets a
      JOIN geo_streets b
        ON a.name = b.name AND a.id <> b.id AND ST_DWithin(a.geometry, b.geometry, 0.0005)
      GROUP BY a.id
      """)

    connected = Map.new(rows, fn [id, ids] -> {id, ids} end)

    from(s in GeoStreet,
      select: %{
        id: s.id,
        name: s.name,
        district: s.district,
        ortsteil: s.ortsteil,
        number_count: s.street_number_count
      }
    )
    |> Repo.all()
    |> Enum.map(&Map.put(&1, :connected, Map.get(connected, &1.id, [])))
  end

  def put_index(index) do
    :persistent_term.put(@index_key, index)
    index
  end

  def get_index do
    case :persistent_term.get(@index_key, nil) do
      nil ->
        # Nobody loaded the index (no `AnalyzeText`, no `load_index/0`). Matching
        # would silently find nothing, which looks like bad data, not a bug.
        Logger.warning("address matching without an index, see AddressMatcher.load_index/0")
        build_index([], [])

      index ->
        index
    end
  end

  @doc """
  Builds the index from street maps (`id`, `name`, `district`, optional
  `ortsteil`, `number_count` and `connected`) and place maps (`id`, `name`, `district`,
  `type`).
  """
  def build_index(streets, places) do
    streets =
      Enum.map(streets, &Map.merge(%{ortsteil: nil, number_count: 0, connected: []}, &1))

    street_entries =
      streets
      |> Enum.reject(&(is_nil(&1.name) or String.length(&1.name) < 3))
      |> Enum.group_by(&name_key(&1.name))

    street_names = MapSet.new(Map.keys(street_entries))

    ortsteile =
      streets
      |> Enum.reject(&is_nil(&1.ortsteil))
      |> Enum.map(&{&1.ortsteil, &1.district})
      |> Enum.uniq()

    ortsteil_names = MapSet.new(ortsteile, fn {ortsteil, _} -> name_key(ortsteil) end)

    place_entries =
      places
      |> Enum.reject(fn place ->
        is_nil(place.name) or String.length(place.name) < 3 or
          ambiguous_place?(place, street_names, ortsteil_names)
      end)
      |> Enum.group_by(&name_key(&1.name))

    trie =
      %{}
      |> add_to_trie(street_entries, &name_variants/1, :street)
      |> add_to_trie(place_entries, &place_variants/1, :place)
      |> Map.new(fn {first, entries} ->
        {first, Enum.sort_by(Enum.uniq(entries), fn {tokens, _, _} -> -length(tokens) end)}
      end)

    ortsteil_trie =
      ortsteile
      |> Enum.group_by(fn {ortsteil, _} -> tokens_of(ortsteil) end, fn {_, district} ->
        district
      end)

    %{
      trie: trie,
      streets: street_entries,
      places: place_entries,
      ortsteile: ortsteil_trie,
      ortsteil_streets: MapSet.intersection(street_names, ortsteil_names)
    }
  end

  # Names that can't be told apart from a street or an Ortsteil
  defp ambiguous_place?(place, street_names, ortsteil_names) do
    key = name_key(place.name)

    case place.type do
      # LOR planning areas are named after the streets and Ortsteile in them
      "LOR" -> MapSet.member?(street_names, key) or MapSet.member?(ortsteil_names, key)
      # "Halensee" and "Nikolassee" are lakes, in a text they are the Ortsteil
      "Water" -> MapSet.member?(ortsteil_names, key)
      _ -> false
    end
  end

  defp add_to_trie(trie, entries, variants_fun, kind) do
    Enum.reduce(entries, trie, fn {key, [first | _]}, trie ->
      first.name
      |> variants_fun.()
      |> Enum.reduce(trie, fn tokens, trie ->
        Map.update(trie, hd(tokens), [{tokens, kind, key}], &[{tokens, kind, key} | &1])
      end)
    end)
  end

  defp name_key(name), do: name |> tokens_of() |> Enum.join(" ")

  # Adjectives can be declined ("Alter Schönefelder Weg" -> "am Alten
  # Schönefelder Weg") and the last word can be a genitive ("des Stuttgarter Platzes")
  defp name_variants(name) do
    tokens = tokens_of(name)

    first_variants =
      case tokens do
        [first, _ | _] ->
          stem = Regex.replace(~r/(er|es|e|en|em)$/u, first, "")

          if String.length(stem) >= 3 and stem != first do
            Enum.map(~w(e er es en em), &(stem <> &1))
          else
            [first]
          end

        [first | _] ->
          [first]
      end

    last = List.last(tokens)

    last_variants =
      if Regex.match?(
           ~r/(platz|markt|damm|weg|park|ring|steig|pfad|garten|hof|graben|kanal)$/u,
           last
         ) do
        [last, last <> "es", last <> "s"]
      else
        [last]
      end

    for first <- Enum.uniq(first_variants), last <- last_variants do
      case tokens do
        [_single] -> [last]
        [_ | rest] -> [first | Enum.drop(rest, -1)] ++ [last]
      end
    end
    |> Enum.uniq()
  end

  defp place_variants(name) do
    variants = name_variants(name)

    kiez_variants =
      Enum.flat_map(variants, fn tokens ->
        last = List.last(tokens)

        cond do
          String.ends_with?(last, "viertel") ->
            [Enum.drop(tokens, -1) ++ [String.replace_suffix(last, "viertel", "kiez")]]

          String.ends_with?(last, "kiez") ->
            [Enum.drop(tokens, -1) ++ [String.replace_suffix(last, "kiez", "viertel")]]

          true ->
            []
        end
      end)

    Enum.uniq(variants ++ kiez_variants)
  end

  ## Text normalization and tokens

  @doc false
  def normalize_text(text) do
    text
    # soft hyphens are used for hyphenation in PDFs
    |> String.replace(~r/\x{AD}\s*\n\s*/u, "")
    |> String.replace("\u00AD", "")
    |> String.replace(~r/(\p{L})-\s*\n\s*(\p{Ll})/u, "\\1\\2")
    |> String.replace(~r/\bStrasse\b/u, "Straße")
    |> String.replace(~r/strasse\b/u, "straße")
    |> expand_enumerations()
  end

  # "Bla-, Foo- und Otherstraße" -> "Blastraße, Foostraße und Otherstraße"
  defp expand_enumerations(text) do
    Regex.replace(
      ~r/((?:\p{Lu}[\p{L}]*-,\s*)*\p{Lu}[\p{L}]*-\s+(?:und|oder)\s+\p{Lu}[\p{L}]*?)(straße|allee|weg|platz|damm|ufer|ring|chaussee|gasse|promenade)\b/u,
      text,
      fn _all, prefix, suffix ->
        String.replace(prefix, ~r/(\p{L})-(?=,|\s+(?:und|oder))/u, "\\1#{suffix}") <> suffix
      end
    )
  end

  defp tokens_of(text) do
    ~r/[\p{L}\p{N}]+/u
    |> Regex.scan(text)
    |> List.flatten()
    |> Enum.map(&normalize_token/1)
  end

  defp normalize_token(token) do
    token = String.downcase(token)

    cond do
      String.ends_with?(token, "strasse") -> String.replace_suffix(token, "strasse", "straße")
      String.ends_with?(token, "str") -> String.replace_suffix(token, "str", "straße")
      true -> token
    end
  end

  # Tokens with their position and the characters between them
  defp tokenize(text) do
    matches = Regex.scan(~r/[\p{L}\p{N}]+/u, text, return: :index) |> List.flatten()

    matches
    |> Enum.with_index()
    |> Enum.map(fn {{start, length}, index} ->
      previous_end =
        case index do
          0 ->
            0

          _ ->
            {s, l} = Enum.at(matches, index - 1)
            s + l
        end

      next_start =
        case Enum.at(matches, index + 1) do
          nil -> byte_size(text)
          {s, _} -> s
        end

      raw = binary_part(text, start, length)

      %{
        token: normalize_token(raw),
        raw: raw,
        start: start,
        stop: start + length,
        before: binary_part(text, previous_end, start - previous_end),
        after: binary_part(text, start + length, next_start - start - length)
      }
    end)
  end

  ## Matching

  @doc """
  Analyzes the text. Returns the ids of the found streets, street numbers and
  places.

  Options:
    * `:districts` - districts the text is known to be about
  """
  def analyze(text, options \\ %{}, index \\ get_index()) do
    text = normalize_text(text)
    tokens = tokenize(text) |> List.to_tuple()
    context_districts = options |> Map.get(:districts, []) |> List.wrap()

    mentions = find_mentions(tokens, index, text)

    text_districts =
      (district_names(tokens) ++ ortsteil_districts(tokens, index))
      |> Enum.uniq()

    context = %{
      given: MapSet.new(context_districts),
      text: MapSet.new(text_districts)
    }

    {street_mentions, place_mentions} =
      Enum.split_with(mentions, &(&1.kind == :street))

    street_mentions = Enum.filter(street_mentions, &accept_street_mention?(&1, index))
    resolved_streets = resolve_streets(street_mentions, index, context)

    found_districts =
      resolved_streets
      |> Enum.map(fn {_mention, street, _number} -> street.district end)
      |> MapSet.new()

    places = resolve_places(place_mentions, index, context, resolved_streets, found_districts)

    # a park or school wins over a street (without house number) with the same name
    park_keys =
      places
      |> Enum.filter(&(&1.type in @place_types_before_streets))
      |> MapSet.new(&name_key(&1.name))

    locations = Enum.reject(resolved_streets, fn {mention, _, _} -> mention.office_address end)

    {unresolved, locations} =
      Enum.split_with(locations, fn {_mention, _street, number} -> number == :unresolved end)

    # A missing house number can often be guessed from its known neighbours.
    # What is left keeps the street as context only (no geometry, no point).
    {interpolated, context_streets} = interpolate_numbers(unresolved)

    street_numbers =
      locations
      |> Enum.filter(fn {_mention, _street, number} -> number end)
      |> Enum.map(fn {_mention, _street, number} -> number end)

    streets =
      locations
      |> Enum.reject(fn {mention, _street, number} ->
        number || MapSet.member?(park_keys, mention.key)
      end)
      |> Enum.map(fn {_mention, street, _number} -> street.id end)

    streets = Enum.uniq(streets)

    # A street that is also mentioned on its own keeps its geometry - the
    # unresolved house number doesn't make the other mention less true.
    context_streets = context_streets |> Enum.uniq() |> Enum.reject(&(&1 in streets))

    %{
      streets: streets,
      street_numbers: street_numbers |> Enum.map(& &1.id) |> Enum.uniq(),
      context_streets: context_streets,
      interpolated: interpolated,
      places: places |> Enum.map(& &1.id) |> Enum.uniq()
    }
  end

  defp find_mentions(tokens, index, text, position \\ 0, acc \\ [])

  defp find_mentions(tokens, _index, _text, position, acc) when position >= tuple_size(tokens),
    do: Enum.reverse(acc)

  defp find_mentions(tokens, index, text, position, acc) do
    token = elem(tokens, position)

    match =
      index.trie
      |> Map.get(token.token, [])
      |> Enum.find(fn {name_tokens, _kind, _key} ->
        tokens_match?(tokens, position, name_tokens)
      end)

    case match do
      nil ->
        find_mentions(tokens, index, text, position + 1, acc)

      {name_tokens, _kind, key} ->
        last = position + length(name_tokens) - 1

        if valid_boundaries?(tokens, position, last) do
          {mentions, next_position} = build_mentions(tokens, index, text, position, last, key)
          find_mentions(tokens, index, text, next_position, Enum.reverse(mentions) ++ acc)
        else
          find_mentions(tokens, index, text, position + 1, acc)
        end
    end
  end

  defp build_mentions(tokens, index, text, first, last, key) do
    street? = Map.has_key?(index.streets, key)
    {numbers, consumed} = if street?, do: parse_numbers(tokens, last + 1), else: {[], 0}

    kinds =
      [street: street?, place: Map.has_key?(index.places, key)]
      |> Enum.filter(&elem(&1, 1))
      |> Enum.map(&elem(&1, 0))

    mentions =
      Enum.map(kinds, fn kind ->
        %{
          kind: kind,
          key: key,
          first: first,
          last: last,
          numbers: numbers,
          cue: location_cue?(tokens, first),
          single_word: single_word?(tokens, first, last),
          office_address: numbers != [] and office_address?(tokens, last + consumed, text)
        }
      end)

    {mentions, last + consumed + 1}
  end

  defp tokens_match?(tokens, position, name_tokens) do
    position + length(name_tokens) <= tuple_size(tokens) and
      name_tokens
      |> Enum.with_index(position)
      |> Enum.all?(fn {name_token, index} -> elem(tokens, index).token == name_token end)
  end

  # A name must not be the end of a hyphenated word ("James-Baldwin-Straße" does
  # not contain "Straße 5") or the start of a compound ("Markt- und Mitmachstände")
  defp valid_boundaries?(tokens, first, last) do
    first_token = elem(tokens, first)
    last_token = elem(tokens, last)

    # only a hyphen directly between two words, not a dash in a table ("- -Lange Straße")
    first_token.before != "-" and not String.starts_with?(last_token.after, "-")
  end

  defp single_word?(_tokens, first, last), do: first == last

  defp location_cue?(tokens, position) do
    Enum.any?(@location_cues, fn cue ->
      start = position - length(cue)

      start >= 0 and
        cue
        |> Enum.with_index(start)
        |> Enum.all?(fn {word, index} -> elem(tokens, index).token == word end)
    end)
  end

  # House numbers after a street: "12", "12a", "12 A", "Nr. 12", "12-14",
  # "12/14", "1 und 3", "3, 5 und 7". Five digits are a postal code.
  defp parse_numbers(tokens, position, numbers \\ [], consumed \\ 0) do
    case number_step(tokens, position, numbers) do
      {:skip, skip} ->
        parse_numbers(tokens, position + skip, numbers, consumed + skip)

      {:number, number, length} ->
        parse_numbers(tokens, position + length, [number | numbers], consumed + length)

      :stop ->
        {Enum.reverse(numbers), consumed}
    end
  end

  defp number_step(tokens, position, _numbers) when position >= tuple_size(tokens), do: :stop

  defp number_step(tokens, position, numbers) do
    token = elem(tokens, position)

    cond do
      numbers == [] and token.token == "nr" ->
        {:skip, 1}

      next_number?(tokens, position, numbers) ->
        {number, extra} = number_with_letter(tokens, position)
        {:number, number, 1 + extra}

      numbers != [] and token.token in @enumeration_words and number_token?(tokens, position + 1) ->
        {:skip, 1}

      true ->
        :stop
    end
  end

  defp next_number?(tokens, position, numbers) do
    number_token?(tokens, position) and
      (numbers == [] or number_separator?(elem(tokens, position - 1)))
  end

  @ordinal_words "Januar|Februar|März|April|Mai|Juni|Juli|August|September|Oktober|November|Dezember|Etage|Stock|Obergeschoss|Geschoss"

  defp number_token?(tokens, position) when position >= tuple_size(tokens), do: false

  defp number_token?(tokens, position) do
    token = elem(tokens, position)
    next = if position + 1 < tuple_size(tokens), do: elem(tokens, position + 1)

    # "3. Etage" or "5. Juni" are no house numbers, "Weidenstraße 22. Sie" is
    ordinal? =
      String.starts_with?(String.trim_leading(token.after), ".") and next != nil and
        (Regex.match?(~r/^\p{Ll}/u, next.raw) or
           Regex.match?(~r/^(#{@ordinal_words})$/u, next.raw))

    Regex.match?(~r/^\d{1,4}[a-z]?$/u, token.token) and not ordinal?
  end

  defp number_separator?(previous) do
    Regex.match?(~r/^\s*([-–\/,]|und|oder|bis)?\s*$/u, previous.after) or
      previous.token in @enumeration_words
  end

  defp number_with_letter(tokens, position) do
    token = elem(tokens, position)
    next = if position + 1 < tuple_size(tokens), do: elem(tokens, position + 1)

    if next && String.length(next.token) == 1 && Regex.match?(~r/^[a-z]$/u, next.token) &&
         Regex.match?(~r/^\s?$/u, token.after) && not Regex.match?(~r/^\p{L}/u, next.after) do
      {String.upcase(token.token <> next.token), 1}
    else
      {String.upcase(token.token), 0}
    end
  end

  defp office_address?(tokens, last_number_position, text) do
    last = elem(tokens, min(last_number_position, tuple_size(tokens) - 1))

    following =
      text
      |> binary_part(last.stop, min(40, byte_size(text) - last.stop))
      |> String.replace_invalid()

    if Regex.match?(~r/^\s*,?\s*(Haus \d+,\s*)?(\d\.\s*\p{L}+,\s*)?\d{5}\s+Berlin/u, following) do
      before_start = max(last.start - 300, 0)
      after_stop = min(last.stop + 200, byte_size(text))

      window =
        text
        |> binary_part(before_start, after_stop - before_start)
        |> String.replace_invalid()
        |> String.downcase()

      Enum.any?(@office_words, &String.contains?(window, &1)) and
        Enum.any?(@procedure_words, &String.contains?(window, &1))
    else
      false
    end
  end

  # district names as whole words ("aus Mitteln" is not Mitte)
  defp district_names(tokens) do
    token_list = Tuple.to_list(tokens) |> Enum.map(& &1.token)

    Enum.filter(Berlin.districts(), fn district ->
      contains_sequence?(token_list, tokens_of(district))
    end)
  end

  defp ortsteil_districts(tokens, index) do
    token_list = Tuple.to_list(tokens) |> Enum.map(& &1.token)

    index.ortsteile
    |> Enum.filter(fn {ortsteil_tokens, _districts} ->
      contains_sequence?(token_list, ortsteil_tokens)
    end)
    |> Enum.flat_map(fn {_, districts} -> districts end)
  end

  defp contains_sequence?(list, sequence) do
    length = length(sequence)

    list
    |> Enum.chunk_every(length, 1, :discard)
    |> Enum.any?(&(&1 == sequence))
  end

  ## Streets

  defp accept_street_mention?(mention, index) do
    candidates = Map.fetch!(index.streets, mention.key)

    cond do
      Regex.match?(~r/^\d/u, mention.key) or String.length(mention.key) < 4 -> false
      mention.office_address -> true
      needs_number?(mention, index) -> mention.numbers != []
      true -> trusted_name?(mention, candidates) or mention.numbers != [] or mention.cue
    end
  end

  # Common words, and the two streets that are named like an Ortsteil
  # ("Prenzlauer Berg", "Alt-Treptow"): a text that names them means the Ortsteil,
  # unless it gives a house number. The Ortsteil is read as district context by
  # `ortsteil_districts/2`, so it still helps to place the other streets.
  defp needs_number?(mention, index) do
    MapSet.member?(@stop_names, mention.key) or
      MapSet.member?(index.ortsteil_streets, mention.key)
  end

  # Names of real streets that are no common words: several words, a clear street
  # suffix or a lot of addresses
  defp trusted_name?(mention, candidates) do
    addresses = candidates |> Enum.map(&(&1.number_count || 0)) |> Enum.sum()

    not mention.single_word or strong_suffix?(hd(candidates).name) or addresses >= 10
  end

  defp strong_suffix?(name) do
    name = String.downcase(name)
    Enum.any?(@strong_suffixes, &String.ends_with?(name, &1))
  end

  # Returns a list of {mention, street, street_number | nil}
  defp resolve_streets(mentions, index, context) do
    numbers = load_numbers(mentions, index)

    # Unambiguous streets first, their districts help with the others
    {unambiguous, ambiguous} =
      Enum.split_with(mentions, fn mention ->
        length(Map.fetch!(index.streets, mention.key)) == 1
      end)

    resolved =
      Enum.flat_map(unambiguous, &resolve_mention(&1, index, context, numbers, MapSet.new()))

    found_districts =
      resolved
      |> Enum.reject(fn {mention, _, _} -> mention.office_address end)
      |> MapSet.new(fn {_mention, street, _number} -> street.district end)

    resolved ++
      Enum.flat_map(ambiguous, &resolve_mention(&1, index, context, numbers, found_districts))
  end

  defp resolve_mention(mention, index, context, numbers, found_districts) do
    candidates = Map.fetch!(index.streets, mention.key)

    scored =
      candidates
      |> Enum.map(fn street ->
        matching_numbers = matching_numbers(mention, street, numbers)

        score =
          if(MapSet.member?(context.given, street.district), do: 3, else: 0) +
            if(MapSet.member?(context.text, street.district), do: 2, else: 0) +
            if(MapSet.member?(found_districts, street.district), do: 1, else: 0) +
            if(matching_numbers != [], do: 2, else: 0)

        {score, street, matching_numbers}
      end)
      |> Enum.sort_by(fn {score, street, _} -> {-score, -(street.number_count || 0)} end)

    scored
    |> best_candidates()
    |> Enum.flat_map(fn {_, street, street_numbers} ->
      to_results(mention, street, street_numbers)
    end)
  end

  # The candidate with the highest score. On a tie nothing is taken, unless the
  # tied candidates are parts of one street.
  defp best_candidates([{score, _, _} | _] = scored) do
    case Enum.take_while(scored, fn {other_score, _, _} -> other_score == score end) do
      [best] -> [best]
      tied -> if one_street?(Enum.map(tied, &elem(&1, 1))), do: tied, else: []
    end
  end

  # The streets are parts of one street across district borders when every part
  # can be reached from the first one over parts that touch
  defp one_street?([first | rest]), do: unreached([first], rest) == []

  defp unreached([], rest), do: rest

  defp unreached([street | queue], rest) do
    {touching, rest} = Enum.split_with(rest, &(&1.id in street.connected))
    unreached(queue ++ touching, rest)
  end

  # A street mentioned with a house number we don't know is not the same as a
  # street mentioned on its own: taking the whole street would claim that all of
  # it is meant. It is marked instead and handled in `analyze/3`.
  defp to_results(%{numbers: [_ | _]} = mention, street, []),
    do: [{mention, street, :unresolved}]

  defp to_results(mention, street, []), do: [{mention, street, nil}]

  defp to_results(mention, street, street_numbers) do
    Enum.map(street_numbers, &{mention, street, &1})
  end

  defp matching_numbers(%{numbers: []}, _street, _numbers), do: []

  defp matching_numbers(mention, street, numbers) do
    mention.numbers
    |> Enum.flat_map(&first_matching_number(&1, street, numbers))
    |> Enum.uniq_by(& &1.id)
  end

  defp first_matching_number(number, street, numbers) do
    number
    |> number_candidates()
    |> Enum.find_value(&Map.get(numbers, {street.id, &1}))
    |> List.wrap()
  end

  # "12a" is in the same house as "12", and a number written "05" in the text is
  # "5" in OSM - without that the house looks missing and would be interpolated
  # next to the real one.
  defp number_candidates(number) do
    [number, String.replace(number, ~r/\D+$/u, "")]
    |> Enum.flat_map(&[&1, String.replace(&1, ~r/^0+(?=\d)/, "")])
    |> Enum.uniq()
  end

  defp load_numbers(mentions, index) do
    pairs =
      for mention <- mentions,
          mention.numbers != [],
          street <- Map.fetch!(index.streets, mention.key),
          number <- mention.numbers,
          candidate <- number_candidates(number),
          do: {street.id, candidate}

    if pairs == [] do
      %{}
    else
      street_ids = pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
      number_values = pairs |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

      from(n in GeoStreetNumber,
        where: n.geo_street_id in ^street_ids and n.number in ^number_values,
        select: %{id: n.id, geo_street_id: n.geo_street_id, number: n.number}
      )
      |> Repo.all()
      |> Map.new(&{{&1.geo_street_id, &1.number}, &1})
    end
  end

  ## Interpolated house numbers

  # Guesses where a house number that is missing in OSM sits. A number is only
  # interpolated when it lies *between* two known numbers of the same street,
  # preferably on the same side (odd/even): two neighbours give the gradient to
  # interpolate along, a single one would only tell us where that one house is.
  # Numbers outside the known range are not extrapolated.
  #
  # Returns {interpolated, context_street_ids} - the streets whose numbers could
  # not be interpolated keep the mention as context only.
  defp interpolate_numbers([]), do: {[], []}

  defp interpolate_numbers(unresolved) do
    street_ids = unresolved |> Enum.map(fn {_mention, street, _} -> street.id end) |> Enum.uniq()
    known = known_numbers(street_ids)
    geometries = street_geometries(street_ids)

    results =
      unresolved
      |> Enum.flat_map(fn {mention, street, _} -> Enum.map(mention.numbers, &{street, &1}) end)
      |> Enum.uniq()
      |> Enum.map(fn {street, number} ->
        {street, interpolate_number(street, number, known, geometries)}
      end)

    interpolated = results |> Enum.map(&elem(&1, 1)) |> Enum.reject(&is_nil/1)
    interpolated_streets = MapSet.new(interpolated, & &1.geo_street_id)

    context =
      results
      |> Enum.filter(fn {_street, point} -> is_nil(point) end)
      |> Enum.map(fn {street, _point} -> street.id end)
      |> Enum.reject(&MapSet.member?(interpolated_streets, &1))
      |> Enum.uniq()

    {interpolated, context}
  end

  defp interpolate_number(street, number, known, geometries) do
    with {:ok, target} <- house_number(number),
         neighbours when neighbours != [] <- Map.get(known, street.id, []),
         {lower, upper} <- bracket(neighbours, target),
         fraction = (target - lower.value) / (upper.value - lower.value),
         %Geo.Point{} = point <-
           interpolate_point(Map.get(geometries, street.id), lower, upper, fraction) do
      neighbour = if fraction <= 0.5, do: lower, else: upper

      %{
        geo_street_id: street.id,
        number: number,
        geo_point: point,
        zip: neighbour.zip,
        ortsteil: neighbour.ortsteil
      }
    else
      _ -> nil
    end
  end

  defp bracket(neighbours, target) do
    same_side = Enum.filter(neighbours, &(rem(&1.value, 2) == rem(target, 2)))

    bracket_in(same_side, target) || bracket_in(neighbours, target)
  end

  defp bracket_in(neighbours, target) do
    lower =
      neighbours
      |> Enum.filter(&(&1.value < target))
      |> Enum.sort_by(& &1.value, :desc)
      |> List.first()

    upper =
      neighbours |> Enum.filter(&(&1.value > target)) |> Enum.sort_by(& &1.value) |> List.first()

    if lower && upper, do: {lower, upper}
  end

  # "12a" and "12 A" are the same house as far as the position is concerned
  defp house_number(number) when is_binary(number) do
    case Integer.parse(number) do
      {value, _rest} when value > 0 -> {:ok, value}
      _ -> :error
    end
  end

  defp house_number(_number), do: :error

  defp known_numbers([]), do: %{}

  defp known_numbers(street_ids) do
    from(n in GeoStreetNumber,
      where: n.geo_street_id in ^street_ids and not is_nil(n.geo_point),
      select: %{
        geo_street_id: n.geo_street_id,
        number: n.number,
        zip: n.zip,
        ortsteil: n.ortsteil,
        geo_point: n.geo_point
      }
    )
    |> Repo.all()
    |> Enum.flat_map(fn row ->
      case house_number(row.number) do
        {:ok, value} -> [Map.put(row, :value, value)]
        :error -> []
      end
    end)
    |> Enum.group_by(& &1.geo_street_id)
  end

  defp street_geometries([]), do: %{}

  defp street_geometries(street_ids) do
    from(s in GeoStreet,
      where: s.id in ^street_ids and not is_nil(s.geometry),
      select: {s.id, s.geometry}
    )
    |> Repo.all()
    |> Map.new()
  end

  # Along the street if we have a line to walk on (house numbers follow the
  # street, not the straight line between two houses), otherwise between the two
  # neighbours. ST_LineLocatePoint only takes a LineString, streets that fall
  # apart into several parts use the straight line.
  defp interpolate_point(%Geo.LineString{} = geometry, lower, upper, fraction) do
    sql = """
    WITH line AS (SELECT ST_GeomFromEWKT($1) AS geom)
    SELECT ST_AsEWKT(
             ST_LineInterpolatePoint(
               geom,
               greatest(0, least(1, lo + $4 * (hi - lo)))))
    FROM (
      SELECT geom,
             ST_LineLocatePoint(geom, ST_GeomFromEWKT($2)) AS lo,
             ST_LineLocatePoint(geom, ST_GeomFromEWKT($3)) AS hi
      FROM line
    ) positions
    """

    params = [
      Geo.WKT.encode!(geometry),
      Geo.WKT.encode!(lower.geo_point),
      Geo.WKT.encode!(upper.geo_point),
      fraction
    ]

    case Repo.query!(sql, params) do
      %{rows: [[ewkt]]} when is_binary(ewkt) -> Geo.WKT.decode!(ewkt)
      _ -> nil
    end
  end

  defp interpolate_point(_geometry, lower, upper, fraction) do
    straight_point(lower.geo_point, upper.geo_point, fraction)
  end

  defp straight_point(%Geo.Point{coordinates: {x1, y1}}, %Geo.Point{coordinates: {x2, y2}}, t) do
    %Geo.Point{coordinates: {x1 + t * (x2 - x1), y1 + t * (y2 - y1)}, srid: 4326}
  end

  defp straight_point(_lower, _upper, _fraction), do: nil

  ## Places

  defp resolve_places(mentions, index, context, resolved_streets, found_districts) do
    street_keys_with_numbers =
      resolved_streets
      |> Enum.filter(fn {_mention, _street, number} -> number end)
      |> MapSet.new(fn {mention, _, _} -> mention.key end)

    street_keys = MapSet.new(resolved_streets, fn {mention, _, _} -> mention.key end)
    districts = context.given |> MapSet.union(context.text) |> MapSet.union(found_districts)

    mentions
    |> Enum.reject(&MapSet.member?(street_keys_with_numbers, &1.key))
    |> Enum.flat_map(fn mention ->
      candidates = Map.fetch!(index.places, mention.key)

      # A street with the same name wins over the places that are named after one
      candidates =
        if MapSet.member?(street_keys, mention.key),
          do: Enum.filter(candidates, &(&1.type in @place_types_before_streets)),
          else: candidates

      # LOR planning areas in a district where streets were found are too coarse
      candidates =
        Enum.reject(
          candidates,
          &(&1.type == "LOR" and MapSet.member?(found_districts, &1.district))
        )

      in_context = Enum.filter(candidates, &MapSet.member?(districts, &1.district))

      chosen =
        cond do
          in_context != [] ->
            in_context

          # generic names like "Rosengarten" need a matching district
          mention.single_word and MapSet.size(context.given) > 0 ->
            []

          length(Enum.uniq_by(candidates, & &1.district)) == 1 ->
            candidates

          true ->
            []
        end

      chosen
      |> Enum.group_by(& &1.district)
      |> Enum.map(fn {_district, places} ->
        Enum.min_by(places, &Map.get(@place_type_order, &1.type, 3))
      end)
    end)
  end
end
