defmodule Hierbautberlin.GeoData.Relevance do
  @moduledoc """
  How relevant an item is for people living nearby. Used to sort the list next
  to the map.

  Every item gets

    * a period in which it matters (`relevant_from` to `relevant_until`): a
      participation phase, the date of an event, a deadline, a construction period,
    * an `importance`: 3 for things people can take part in, 1.5 for events,
      construction and closures, 1 for everything else and 0.3 for small
      administrative details,
    * a `relevance_half_life` in days: how fast an item becomes unimportant
      after its period is over.

  The score depends on the current time and the map position, so it is calculated
  in the database (see `MapFeatures.list_items/3` and the
  `relevance_time_factor` SQL function):

      importance * time factor * distance factor

  Press releases usually matter only for a short time, but then a lot: without a
  date in the text they are relevant for six weeks (instead of two), and during
  these six weeks their score is multiplied by four (`fresh_news_sql/2`), so they
  are above ongoing participations. Events that are over still lose their
  relevance, the multiplier doesn't change the time factor.
  """

  import Ecto.Query, warn: false

  alias Hierbautberlin.GeoData.NewsItem
  alias Hierbautberlin.Repo

  @participation 3.0
  @notable 1.5
  @normal 1.0
  @minor 0.3

  # Press releases high up for six weeks, see the moduledoc
  @fresh_sources ~w(BERLIN_PRESSE)
  @fresh_days 42
  @fresh_boost 4.0

  # How long a news item without any date in its text stays relevant
  @news_days 14
  @participation_days 30

  @months ~w(januar februar märz april mai juni juli august september oktober november dezember)

  # People can take part or object
  @participation_words ~r/\b(Einwendungen|Anregungen|Bürgerbeteiligung|Online-Beteiligung|Öffentlichkeitsbeteiligung|Beteiligungsverfahren|öffentlich(e|en)? ausgelegt|öffentliche Auslegung|Bürgerversammlung|Einwohnerversammlung|Informationsveranstaltung|Beteiligen Sie sich|Stellungnahmen? .{0,80}(abgegeben|eingereicht|vorgebracht) werden)/iu

  # Something happens at a place and date
  @event_words ~r/\b(Einladung|lädt\b.{0,80}\bein\b|laden\b.{0,80}\bein\b|Veranstaltung|Kiezspaziergang|Sprechstunde|Führungen?|Workshop|Fest|Festival|Aktionstag|Tag der offenen Tür|Rundgang|Sitzung|Mitmach)/iu

  # Affects daily life around the place
  @disruption_words ~r/\b(Bauarbeiten|Baumaßnahmen?|Baubeginn|Sperrung|gesperrt|Vollsperrung|Umleitung|Baumfällungen?|Fällarbeiten|Umgestaltung|Straßenbau|Leitungsarbeiten|geschlossen|Schließtag|Schließung|Allgemeinverfügung)/iu

  # Administrative details (mostly Amtsblatt)
  @minor_titles ~r/^(Grundstücksnummerierung|Festsetzung(\/Aufhebung)? (einer|von) Grundstücksnummer|Ungültigkeitserklärung|Entstehung einer Stiftung|Aufhebung einer Stiftung|Rechtsgeschäftliche Vertretung|Jahresabschluss|Eingruppierung|Öffentliche Versteigerung|Verwaltungsvorschrift|Ausführungsvorschrift|Rundschreiben|Gemeinsamer Tarif|Geschäftsstelle|Zuständige Stelle|Bezirksämter$|Gebührenordnung|Beitragsordnung|Wahlordnung|Ersatz|Bekanntmachung über (Veränderungen bei den Mitgliedern|die Wahl zum Beirat)|Berufung von Mitgliedern)/u

  @doc """
  SQL condition: the news item with these columns is a fresh press release.
  """
  def fresh_news_sql(published_at, source_id) do
    sources = Enum.map_join(@fresh_sources, ", ", &"'#{&1}'")

    """
    (#{published_at} > now() AT TIME ZONE 'UTC' - interval '#{@fresh_days} days'
     AND #{source_id} IN (SELECT id FROM sources WHERE short_name IN (#{sources})))
    """
  end

  @doc """
  Factor for the score of fresh press releases.
  """
  def fresh_boost, do: @fresh_boost

  @doc """
  Relevance of a news item, based on its title, text, publication date and the
  short name of its source.
  """
  def for_news_item(title, text, published_at, source \\ nil)

  def for_news_item(title, text, %DateTime{} = published_at, source) do
    title = title || ""
    text = Enum.join([title, text || ""], "\n")
    deadline = latest_date(text, published_at)

    {importance, default_days, half_life} = classify(title, text, deadline)

    default_days =
      if source in @fresh_sources, do: max(default_days, @fresh_days), else: default_days

    %{
      importance: importance,
      relevant_from: published_at,
      relevant_until: deadline || DateTime.add(published_at, default_days, :day),
      relevance_half_life: half_life
    }
  end

  def for_news_item(_title, _text, nil, _source) do
    %{importance: @normal, relevant_from: nil, relevant_until: nil, relevance_half_life: 30}
  end

  # {importance, days relevant without a date in the text, half life}
  defp classify(title, text, deadline) do
    cond do
      Regex.match?(@minor_titles, title) -> {@minor, @news_days, 30}
      Regex.match?(@participation_words, text) -> participation(deadline)
      Regex.match?(@disruption_words, text) -> {@notable, @news_days, 14}
      deadline && Regex.match?(@event_words, text) -> {@notable, @news_days, 3}
      true -> {@normal, @news_days, 30}
    end
  end

  defp participation(nil), do: {2.0, @participation_days, 7}
  defp participation(_deadline), do: {@participation, @participation_days, 7}

  @doc """
  Calculates the relevance of all news items again, e.g. after these rules
  changed. Returns the number of updated news items.
  """
  def update_news_items do
    from(n in NewsItem,
      join: s in assoc(n, :source),
      select: %{
        id: n.id,
        title: n.title,
        text: coalesce(n.full_text, n.content),
        published_at: n.published_at,
        source: s.short_name
      }
    )
    |> Repo.all(timeout: :infinity)
    |> Enum.chunk_every(500)
    |> Enum.reduce(0, fn chunk, count ->
      Repo.transaction(fn -> Enum.each(chunk, &update_news_item/1) end)
      count + length(chunk)
    end)
  end

  defp update_news_item(item) do
    relevance = for_news_item(item.title, item.text, item.published_at, item.source)

    from(n in NewsItem, where: n.id == ^item.id)
    |> Repo.update_all(set: Enum.to_list(relevance))
  end

  @doc """
  Relevance of a geo item. Importers can set `importance`, `relevant_from`,
  `relevant_until` and `relevance_half_life` when they know better (e.g. the
  participation phase), the rest is derived from the dates of the item.
  """
  def for_geo_item(attrs) do
    participation? = attrs[:participation_open] == true
    {from, until} = geo_item_period(attrs)

    defaults = %{
      importance: if(participation?, do: @participation, else: @normal),
      relevant_from: from,
      relevant_until: until,
      relevance_half_life: if(participation?, do: 14, else: 180)
    }

    Map.merge(defaults, Map.take(attrs, Map.keys(defaults)), fn _key, default, value ->
      if is_nil(value), do: default, else: value
    end)
  end

  defp geo_item_period(attrs) do
    case {attrs[:date_start], attrs[:date_end], attrs[:date_updated]} do
      {nil, nil, updated} -> {updated, updated}
      {nil, date_end, _} -> {date_end, date_end}
      {date_start, nil, _} -> {date_start, date_start}
      {date_start, date_end, _} -> {date_start, date_end}
    end
  end

  @doc """
  The deadline or the date of an event mentioned in the text: dates after
  "bis", "spätestens", "Frist" etc. win, otherwise the latest date. Only dates
  after the publication and at most a year later count, start dates ("ab 1. Mai")
  are ignored.
  """
  def latest_date(text, %DateTime{} = published_at) do
    published = DateTime.to_date(published_at)
    latest_allowed = Date.add(published, 366)

    dates =
      (full_dates(text) ++ month_dates(text) ++ relative_dates(text, published))
      |> Enum.filter(fn {date, _kind} ->
        Date.compare(date, published) == :gt and Date.compare(date, latest_allowed) != :gt
      end)

    deadlines = for {date, :deadline} <- dates, do: date
    others = for {date, :other} <- dates, do: date

    case if(deadlines == [], do: others, else: deadlines) do
      [] -> nil
      candidates -> candidates |> Enum.max(Date) |> DateTime.new!(~T[23:59:59], "Etc/UTC")
    end
  end

  @deadline_context ~r/\b(bis|spätestens|Frist|einschließlich|endet|läuft|zum)\b[^.]{0,25}$/iu
  @start_context ~r/\b(ab|seit)\s*$/iu

  # "12.09.2026", "12. September 2026"
  defp full_dates(text) do
    numeric = ~r/\b(\d{1,2})\.\s?(\d{1,2})\.\s?(\d{4})\b/u
    named = ~r/\b(\d{1,2})\.\s*(#{Enum.join(@months, "|")})\s+(\d{4})\b/iu

    scan_dates(numeric, text, fn [day, month, year] -> to_date(year, month, day) end) ++
      scan_dates(named, text, fn [day, month, year] ->
        to_date(year, month_number(month), day)
      end)
  end

  # "bis Ende Oktober 2026", "bis voraussichtlich Dezember 2026"
  defp month_dates(text) do
    ~r/\bbis\s+(?:(?:voraussichtlich|Ende|Mitte|Anfang|einschließlich|zum)\s+)*(#{Enum.join(@months, "|")})\s+(\d{4})\b/iu
    |> scan_dates(text, fn [month, year] ->
      case to_date(year, month_number(month), 1) do
        nil -> nil
        date -> Date.end_of_month(date)
      end
    end)
    |> Enum.map(fn {date, _kind} -> {date, :deadline} end)
  end

  # Returns {date, :deadline | :other} for every match, start dates are dropped
  defp scan_dates(regex, text, to_date) do
    regex
    |> Regex.scan(text, return: :index)
    |> Enum.flat_map(fn [{start, _length} | groups] ->
      before = text |> binary_part(max(start - 40, 0), min(start, 40)) |> String.replace_invalid()

      values =
        Enum.map(groups, fn {group_start, length} -> binary_part(text, group_start, length) end)

      cond do
        Regex.match?(@start_context, before) -> []
        date = to_date.(values) -> [{date, date_kind(before)}]
        true -> []
      end
    end)
  end

  defp date_kind(before) do
    if Regex.match?(@deadline_context, before), do: :deadline, else: :other
  end

  # "innerhalb eines Monats", "innerhalb von drei Monaten"
  defp relative_dates(text, published) do
    ~r/\binnerhalb\s+(?:von\s+)?(eines|einem|einer|zwei|drei|vier|sechs|\d+)\s+(Monats?|Monaten|Wochen?)\b/iu
    |> Regex.scan(text, capture: :all_but_first)
    |> Enum.map(fn [count, unit] ->
      count = count_number(String.downcase(count))

      date =
        if String.starts_with?(String.downcase(unit), "woche"),
          do: Date.add(published, count * 7),
          else: Date.shift(published, month: count)

      {date, :deadline}
    end)
  end

  defp count_number(word) when word in ~w(eines einem einer), do: 1
  defp count_number("zwei"), do: 2
  defp count_number("drei"), do: 3
  defp count_number("vier"), do: 4
  defp count_number("sechs"), do: 6
  defp count_number(number), do: String.to_integer(number)

  defp month_number(name) do
    Enum.find_index(@months, &(&1 == String.downcase(name))) + 1
  end

  defp to_date(year, month, day) do
    with {year, ""} <- Integer.parse(to_string(year)),
         {month, ""} <- Integer.parse(to_string(month)),
         {day, ""} <- Integer.parse(to_string(day)),
         {:ok, date} <- Date.new(year, month, day) do
      date
    else
      _ -> nil
    end
  end
end
