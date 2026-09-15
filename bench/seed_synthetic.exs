# Seeds a database with synthetic, production-like amounts of data in Berlin.
#
#     DATABASE_PORT=5434 mix run bench/seed_synthetic.exs
#
# Numbers are rough guesses of the production database size.
import Ecto.Query

alias Hierbautberlin.Repo
alias Hierbautberlin.GeoData.{GeoItem, GeoPlace, GeoStreet, NewsItem, Source}

:rand.seed(:exsss, {1, 2, 3})

counts = %{streets: 10_000, places: 3_000, geo_items: 12_000, news_items: 25_000}
{min_lng, max_lng, min_lat, max_lat} = {13.09, 13.76, 52.34, 52.68}
now = DateTime.utc_now() |> DateTime.truncate(:second)

rand_point = fn ->
  {min_lng + :rand.uniform() * (max_lng - min_lng), min_lat + :rand.uniform() * (max_lat - min_lat)}
end

walk = fn {lng, lat}, steps, step ->
  Enum.scan(1..steps, {lng, lat}, fn _, {x, y} ->
    {x + (:rand.uniform() - 0.5) * step, y + (:rand.uniform() - 0.5) * step * 0.6}
  end)
end

polygon = fn {lng, lat}, radius ->
  ring =
    for i <- 0..23 do
      angle = i / 24 * 2 * :math.pi()
      r = radius * (0.6 + :rand.uniform() * 0.4)
      {lng + :math.cos(angle) * r, lat + :math.sin(angle) * r * 0.6}
    end

  %Geo.Polygon{coordinates: [ring ++ [hd(ring)]], srid: 4326}
end

random_date = fn -> DateTime.add(now, -:rand.uniform(365 * 6) * 86_400, :second) end

Repo.query!(
  "TRUNCATE geo_streets, geo_street_numbers, geo_places, geo_items, news_items, sources RESTART IDENTITY CASCADE"
)

sources =
  for {name, color} <- [
        {"BPLAN", "#e6194b"},
        {"MEIN_BERLIN", "#3cb44b"},
        {"INFRAVELO", "#4363d8"},
        {"PRESSE", "#f58231"},
        {"AMTSBLATT", "#911eb4"}
      ] do
    Repo.insert!(%Source{
      short_name: name,
      name: name,
      url: "https://example.com",
      copyright: name,
      color: color,
      background_color: color
    })
  end

insert_chunks = fn schema, rows ->
  rows |> Enum.chunk_every(1_000) |> Enum.each(&Repo.insert_all(schema, &1))
end

IO.puts("streets")

insert_chunks.(
  GeoStreet,
  for i <- 1..counts.streets do
    start = rand_point.()
    coords = walk.(start, 12, 0.002)

    %{
      name: "Straße #{i}",
      city: "Berlin",
      district: "Mitte",
      geometry: %Geo.LineString{coordinates: coords, srid: 4326},
      geo_point: %Geo.Point{coordinates: Enum.at(coords, 6), srid: 4326},
      street_number_count: 20,
      inserted_at: now,
      updated_at: now
    }
  end
)

IO.puts("places")

insert_chunks.(
  GeoPlace,
  for i <- 1..counts.places do
    center = rand_point.()

    %{
      external_id: "place-#{i}",
      name: "Park #{i}",
      city: "Berlin",
      district: "Mitte",
      type: "Park",
      geometry: polygon.(center, 0.002 + :rand.uniform() * 0.004),
      geo_point: %Geo.Point{coordinates: center, srid: 4326},
      inserted_at: now,
      updated_at: now
    }
  end
)

IO.puts("geo items")

insert_chunks.(
  GeoItem,
  for i <- 1..counts.geo_items do
    center = rand_point.()
    kind = :rand.uniform(3)
    source = Enum.at(sources, rem(i, 3))
    date = random_date.()

    %{
      external_id: "item-#{i}",
      title: "Projekt #{i}",
      subtitle: "Untertitel #{i}",
      description: String.duplicate("Beschreibung des Projektes. ", 20),
      url: "https://example.com/#{i}",
      state: "in_planning",
      source_id: source.id,
      date_updated: date,
      date_start: date,
      participation_open: rem(i, 17) == 0,
      hidden: false,
      geo_point: if(kind != 2, do: %Geo.Point{coordinates: center, srid: 4326}),
      geometry:
        case kind do
          1 -> nil
          2 -> polygon.(center, 0.001 + :rand.uniform() * 0.003)
          3 -> %Geo.LineString{coordinates: walk.(center, 30, 0.001), srid: 4326}
        end,
      inserted_at: now,
      updated_at: now
    }
  end
)

IO.puts("news items")

insert_chunks.(
  NewsItem,
  for i <- 1..counts.news_items do
    source = Enum.at(sources, 3 + rem(i, 2))

    %{
      external_id: "news-#{i}",
      title: "Pressemitteilung #{i}",
      content: String.duplicate("Inhalt der Pressemitteilung. ", 15),
      url: "https://example.com/news/#{i}",
      published_at: random_date.(),
      source_id: source.id,
      hidden: false,
      inserted_at: now,
      updated_at: now
    }
  end
)

IO.puts("news links")

street_ids = Repo.all(from s in GeoStreet, select: s.id) |> List.to_tuple()
place_ids = Repo.all(from p in GeoPlace, select: p.id) |> List.to_tuple()
news_ids = Repo.all(from n in NewsItem, select: n.id)

pick = fn tuple -> elem(tuple, :rand.uniform(tuple_size(tuple)) - 1) end

street_links =
  for news_id <- news_ids, _ <- 1..:rand.uniform(3) do
    %{news_item_id: news_id, geo_street_id: pick.(street_ids)}
  end
  |> Enum.uniq()

place_links =
  for news_id <- news_ids, :rand.uniform(3) == 1 do
    %{news_item_id: news_id, geo_place_id: pick.(place_ids)}
  end

street_links
|> Enum.chunk_every(5_000)
|> Enum.each(&Repo.insert_all("geo_streets_news_items", &1))

place_links
|> Enum.chunk_every(5_000)
|> Enum.each(&Repo.insert_all("geo_places_news_items", &1))

IO.puts("cached news geometries")

Repo.query!(
  """
  UPDATE news_items n SET
    geometries = sub.geometries,
    geo_points = sub.geo_points
  FROM (
    SELECT n.id,
      ST_ForceCollection(ST_Collect(g.geometry)) AS geometries,
      ST_Collect(g.geo_point) AS geo_points
    FROM news_items n
    JOIN (
      SELECT l.news_item_id, s.geometry, s.geo_point FROM geo_streets_news_items l JOIN geo_streets s ON s.id = l.geo_street_id
      UNION ALL
      SELECT l.news_item_id, p.geometry, p.geo_point FROM geo_places_news_items l JOIN geo_places p ON p.id = l.geo_place_id
    ) g ON g.news_item_id = n.id
    GROUP BY n.id
  ) sub
  WHERE sub.id = n.id
  """,
  [],
  timeout: :infinity
)

Repo.query!("ANALYZE")
IO.puts("done")
