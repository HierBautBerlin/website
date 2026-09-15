# Measures how long loading the map data takes and how big the payload is.
#
#     DATABASE_PORT=5434 mix run bench/map_bench.exs
#
# Run bench/seed_synthetic.exs first if you have no real data.
Logger.configure(level: :warning)

alias Hierbautberlin.GeoData.MapFeatures

locations = [
  {"Mitte", 52.5166, 13.3781},
  {"Kreuzberg", 52.4986, 13.4033},
  {"Spandau", 52.5355, 13.1995},
  {"Köpenick", 52.4449, 13.5774},
  {"Pankow", 52.5693, 13.4012}
]

measure = fn fun, runs ->
  # warm up
  fun.()

  times =
    for _ <- 1..runs do
      {micro, _} = :timer.tc(fun)
      micro / 1000
    end

  sorted = Enum.sort(times)
  %{median: Enum.at(sorted, div(runs, 2)), max: List.last(sorted)}
end

MapFeatures.refresh()

tile_for = fn lat, lng, zoom ->
  n = :math.pow(2, zoom)
  lat_rad = lat * :math.pi() / 180
  x = trunc((lng + 180) / 360 * n)
  y = trunc((1 - :math.log(:math.tan(lat_rad) + 1 / :math.cos(lat_rad)) / :math.pi()) / 2 * n)
  {x, y}
end

IO.puts("| Location | zoom | list median ms | list max ms | items | tile median ms | tile KB |")
IO.puts("|---|---|---|---|---|---|---|")

for {name, lat, lng} <- locations, zoom <- [12, 14, 16] do
  center = %{lat: lat, lng: lng}
  bounds = MapFeatures.bounds_around(center, zoom)
  list = measure.(fn -> MapFeatures.list_items(bounds, center) end, 10)
  {x, y} = tile_for.(lat, lng, zoom)
  tile = measure.(fn -> MapFeatures.tile(zoom, x, y) end, 10)

  IO.puts(
    "| #{name} | #{zoom} | #{Float.round(list.median, 1)} | #{Float.round(list.max, 1)} | " <>
      "#{length(MapFeatures.list_items(bounds, center))} | #{Float.round(tile.median, 1)} | " <>
      "#{Float.round(byte_size(MapFeatures.tile(zoom, x, y)) / 1024, 1)} |"
  )
end
