defmodule Hierbautberlin.GeoData do
  import Ecto.Query, warn: false

  alias Hierbautberlin.{PostgresQueryHelper, Repo}

  alias Hierbautberlin.GeoData.{
    AnalyzeText,
    GeoItem,
    GeoPlace,
    GeoPosition,
    GeoStreet,
    GeoStreetNumber,
    NewsItem,
    Source
  }

  def get_source!(id) do
    Repo.get!(Source, id)
  end

  def upsert_source(attrs \\ %{}) do
    %Source{}
    |> Source.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: :short_name
    )
  end

  def get_geo_street!(id) do
    Repo.get!(GeoStreet, id)
  end

  def get_geo_street_number!(id) do
    Repo.get!(GeoStreetNumber, id)
  end

  def search_street(search) do
    if String.length(search) < 3 do
      do_simple_street_search(search)
    else
      do_complex_street_search(search)
    end
    |> Repo.all()
  end

  defp do_simple_street_search(search) do
    search_query = "#{search}%"

    from(
      entry in GeoStreet,
      where: ilike(entry.name, ^search_query),
      order_by: [desc: entry.street_number_count],
      limit: 10
    )
  end

  defp do_complex_street_search(search) do
    downcase_search = String.downcase(search)
    formatted_search = PostgresQueryHelper.format_search_query(search)

    from(
      entry in GeoStreet,
      where:
        fragment(
          "? in (select id from geo_streets where (fulltext_search @@ to_tsquery('german', unaccent(?)) or name ilike ?))",
          entry.id,
          ^formatted_search,
          ^"%#{search}%"
        ),
      order_by: [
        desc: entry.street_number_count,
        asc: fragment("levenshtein(?, lower(?), 1, 10, 20), name", ^downcase_search, entry.name)
      ],
      limit: 10
    )
  end

  def get_geo_place!(id) do
    Repo.get!(GeoPlace, id)
  end

  def get_news_item!(id) do
    Repo.get!(NewsItem, id)
    |> Repo.preload([:source])
  end

  def get_geo_item!(id) do
    Repo.get!(GeoItem, id)
    |> Repo.preload([:source])
  end

  def create_geo_item(attrs \\ %{}) do
    %GeoItem{}
    |> GeoItem.changeset(attrs)
    |> Repo.insert()
  end

  def change_geo_item(%GeoItem{} = geo_item), do: GeoItem.changeset(geo_item, %{})

  def upsert_geo_item(attrs \\ %{}) do
    %GeoItem{}
    |> GeoItem.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:source_id, :external_id]
    )
  end

  def get_point(geo_item)

  def get_point(%GeoItem{geo_point: item}) when not is_nil(item) do
    %{coordinates: {lng, lat}} = item
    %{lat: lat, lng: lng}
  end

  def get_point(%GeoItem{geometry: geometry}) when not is_nil(geometry) do
    %{coordinates: {lng, lat}} = Geo.Turf.Measure.center(geometry)
    %{lat: lat, lng: lng}
  end

  def get_point(%GeoPosition{geopoint: item}) when not is_nil(item) do
    %{coordinates: {lng, lat}} = item
    %{lat: lat, lng: lng}
  end

  def get_point(%GeoPosition{geometry: geometry}) when not is_nil(geometry) do
    %{coordinates: {lng, lat}} = Geo.Turf.Measure.center(geometry)
    %{lat: lat, lng: lng}
  end

  def get_point(%NewsItem{geo_points: item}) when not is_nil(item) do
    %{coordinates: [{lng, lat} | _tail]} = item
    %{lat: lat, lng: lng}
  end

  def get_point(%NewsItem{geometries: item}) when not is_nil(item) do
    %{geometries: [geometry | _tail]} = item
    %{coordinates: {lng, lat}} = Geo.Turf.Measure.center(geometry)

    %{lat: lat, lng: lng}
  end

  def get_point(_item) do
    %{lat: nil, lng: nil}
  end

  def get_items_near(lat, lng, count \\ 10) do
    items = GeoItem.get_near(lat, lng, count) ++ NewsItem.get_near(lat, lng, count)

    items
    |> remove_old_items()
    |> sort_by_relevance(%{lat: lat, lng: lng})
    |> Enum.take(count)
  end

  defp remove_old_items(items) do
    five_years_ago = Timex.shift(Timex.today(), years: -5)

    Enum.filter(items, fn item ->
      item.newest_date == nil || Timex.after?(item.newest_date, five_years_ago)
    end)
  end

  defp sort_by_relevance(items, coordinates) do
    {new_items, old_items} = split_items_by_date(items)

    sort_by_date_and_distance(new_items, coordinates) ++
      sort_by_date_and_distance(old_items, coordinates)
  end

  defp split_items_by_date(items) do
    Enum.split_with(items, fn item ->
      item.newest_date && abs(Timex.diff(Timex.now(), item.newest_date, :weeks)) < 6
    end)
  end

  def sort_by_date_and_distance(items, %{lat: lat, lng: lng}) do
    Enum.sort_by(items, fn item ->
      months_difference =
        Timex.diff(
          Timex.now(),
          item.newest_date || Timex.shift(Timex.today(), months: -3),
          :months
        )

      distance =
        item.positions
        |> Enum.map(fn position ->
          %{lat: item_lat, lng: item_lng} = get_point(position)

          Geo.Turf.Measure.distance(
            %Geo.Point{coordinates: {lng, lat}},
            %Geo.Point{coordinates: {item_lng, item_lat}},
            :meters
          )
        end)
        |> Enum.sort()
        |> List.first()

      push_factor =
        if item.participation_open do
          30
        else
          0
        end

      distance / 10 + months_difference - push_factor
    end)
  end

  def with_news(item) do
    Repo.preload(item, news_items: [:source])
  end

  def with_geo_street(item) do
    Repo.preload(item, :geo_street)
  end

  def analyze_text(text, options \\ %{}) do
    AnalyzeText.analyze_text(text, options)
  end

  def create_news_item!(attrs, full_text, districts) do
    result = analyze_text(full_text, %{districts: districts})

    %NewsItem{}
    |> NewsItem.changeset(attrs)
    |> Repo.insert!(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: :external_id
    )
    |> Repo.preload([:geo_streets, :geo_street_numbers, :geo_places])
    |> NewsItem.change_associations(
      geo_streets: result.streets,
      geo_street_numbers: result.street_numbers,
      geo_places: result.places
    )
    |> Repo.update!()
  end
end
