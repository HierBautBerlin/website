defmodule Hierbautberlin.GeoData.AnalyzeText do
  require Logger
  use GenServer
  import Ecto.Query, warn: false

  alias Hierbautberlin.Repo
  alias Hierbautberlin.GeoData.{GeoPlace, GeoStreet, GeoStreetNumber}

  @place_sorting ["Park", "School", "LOR"]

  def init(%{streets: streets, places: places}) when is_list(streets) and is_list(places) do
    street_names = Enum.map(streets, & &1.name)
    place_names = Enum.map(places, & &1.name)

    {:ok,
     %{
       streets: geo_map(%{}, streets),
       places: geo_map(%{}, places),
       street_graph: AhoCorasick.new(street_names),
       place_graph: AhoCorasick.new(place_names)
     }}
  end

  def init(_quizzes), do: {:error, "streets must be a list"}

  def start_link(options \\ []) do
    Logger.debug("Booting street analyzer")
    query = from(streets in GeoStreet, select: [:name, :city, :district])
    streets = Repo.all(query)

    query = from(places in GeoPlace, select: [:name, :city, :district])
    places = Repo.all(query)

    Logger.debug("... with #{length(streets)} Streets and #{length(places)} Places")

    server = GenServer.start_link(__MODULE__, %{streets: streets, places: places}, options)
    Logger.debug("Booting street analyzer completed")
    server
  end

  def handle_call({:add_streets, streets}, _from, state) do
    Enum.each(streets, fn street ->
      AhoCorasick.add_term(state.street_graph, street.name)
    end)

    AhoCorasick.build_trie(state.street_graph)
    {:reply, :ok, Map.merge(state, %{streets: geo_map(state.streets, streets)})}
  end

  def handle_call({:add_places, places}, _from, state) do
    Enum.each(places, fn place ->
      AhoCorasick.add_term(state.place_graph, place.name)
    end)

    AhoCorasick.build_trie(state.place_graph)
    {:reply, :ok, Map.merge(state, %{places: geo_map(state.places, places)})}
  end

  def handle_call({:analyze_text, text, options}, _from, state) do
    options = Map.merge(%{districts: []}, options)

    text = clean_text(text)
    districts = options.districts

    result =
      %{
        streets: [],
        street_numbers: [],
        places: [],
        unclear: %{}
      }
      |> search_street(state, text)
      |> search_place(state, text)

    if Enum.empty?(result.unclear) do
      {:reply,
       result
       |> clean_results()
       |> Map.delete(:unclear), state}
    else
      relevant_districts = Enum.uniq(districts_for(result) ++ districts)

      {:reply,
       result
       |> guess_streets(relevant_districts)
       |> guess_street_numbers(relevant_districts)
       |> guess_place(relevant_districts)
       |> clean_results()
       |> Map.delete(:unclear), state}
    end
  end

  defp clean_results(map) do
    map
    |> remove_lor_if_street_exists()
    |> remove_street_if_place_exists()
    |> remove_place_if_street_number_exists()
  end

  defp remove_lor_if_street_exists(map) do
    street_names = Enum.map(map.streets, & &1.name)
    districts = Enum.map(map.streets, & &1.district)

    Map.merge(map, %{
      places:
        Enum.filter(map.places, fn place ->
          place.type != "LOR" || !(place.district in districts || place.name in street_names)
        end)
    })
  end

  defp remove_place_if_street_number_exists(map) do
    street_names = Enum.map(map.street_numbers, & &1.geo_street.name)

    Map.merge(map, %{
      places:
        Enum.filter(map.places, fn place ->
          !(place.name in street_names)
        end)
    })
  end

  defp remove_street_if_place_exists(map) do
    place_names = Enum.map(map.places, & &1.name)

    Map.merge(map, %{
      streets:
        Enum.filter(map.streets, fn street ->
          !(street.name in place_names)
        end)
    })
  end

  defp search_place(map, state, text) do
    state.place_graph
    |> do_search_place(text)
    |> MapSet.to_list()
    |> Enum.reduce(map, fn {hit, _, _}, acc ->
      places = state.places[hit]

      if length(places) == 1 do
        Map.merge(acc, %{places: map.places ++ places})
      else
        unclear_places = Map.get(acc.unclear, :places, [])

        Map.merge(acc, %{
          unclear: Map.merge(acc.unclear, %{places: unclear_places ++ [places]})
        })
      end
    end)
  end

  defp do_search_place(graph, text) do
    AhoCorasick.search(graph, text)
    |> MapSet.union(
      AhoCorasick.search(
        graph,
        String.replace(text, ~r/(\w+)(viertel)\b/, "\\1kiez")
      )
    )
    |> MapSet.union(
      AhoCorasick.search(
        graph,
        String.replace(text, ~r/(\w+)(kiez)\b/, "\\1viertel")
      )
    )
  end

  defp search_street(map, state, text) do
    state.street_graph
    |> AhoCorasick.search(text)
    |> MapSet.to_list()
    |> Enum.reduce(map, fn {hit, start_pos, length}, acc ->
      number = text |> String.slice(start_pos + length, 10) |> get_street_number()

      if number do
        find_street_number_in(acc, state.streets[hit], number)
      else
        find_street_in(acc, state.streets[hit])
      end
    end)
  end

  defp districts_for(map) do
    street_districts = map.streets |> Enum.map(& &1.district)
    street_number_districts = map.street_numbers |> Enum.map(& &1.geo_street.district)
    place_districts = map.places |> Enum.map(& &1.district)

    Enum.uniq(street_districts ++ street_number_districts ++ place_districts)
  end

  defp find_street_in(acc, streets) do
    if length(streets) == 1 do
      Map.merge(acc, %{streets: acc.streets ++ streets})
    else
      unclear_streets = Map.get(acc.unclear, :streets, [])
      Map.merge(acc, %{unclear: Map.merge(acc.unclear, %{streets: unclear_streets ++ [streets]})})
    end
  end

  defp find_street_number_in(acc, streets, number) do
    street_ids = Enum.map(streets, & &1.id)

    query =
      from number in GeoStreetNumber,
        where: number.geo_street_id in ^street_ids and number.number == ^number

    street_numbers = Repo.all(query) |> Repo.preload(:geo_street)

    found_items = length(street_numbers)

    cond do
      found_items == 0 ->
        if strip_letter(number) != number do
          find_street_number_in(acc, streets, strip_letter(number))
        else
          Map.merge(acc, %{streets: acc.streets ++ streets})
        end

      found_items == 1 ->
        Map.merge(acc, %{street_numbers: acc.street_numbers ++ street_numbers})

      true ->
        unclear_street_numbers = Map.get(acc.unclear, :street_numbers, [])

        Map.merge(acc, %{
          unclear:
            Map.merge(acc.unclear, %{street_numbers: unclear_street_numbers ++ [street_numbers]})
        })
    end
  end

  defp strip_letter(number) do
    result = Regex.named_captures(~r/^(?<number>\d+).*/, number)

    if result do
      result["number"]
    else
      nil
    end
  end

  defp get_street_number(text) do
    result = Regex.named_captures(~r/^(?<number>\d+(\s*[a-zA-Z])?).*/, text)

    if result do
      result["number"]
      |> String.replace(" ", "")
      |> String.upcase()
    else
      nil
    end
  end

  defp guess_streets(%{unclear: unclear} = map, districts) do
    found_streets =
      Enum.map(Map.get(unclear, :streets, []), fn streets ->
        filtered =
          Enum.filter(streets, fn street ->
            Enum.member?(districts, street.district)
          end)

        if Enum.count_until(filtered, 2) == 1 do
          filtered
        else
          nil
        end
      end)
      |> List.flatten()
      |> Enum.filter(fn item ->
        item != nil
      end)

    Map.merge(map, %{streets: map.streets ++ found_streets})
  end

  defp guess_street_numbers(%{unclear: unclear} = map, districts) do
    found_street_numbers =
      unclear
      |> Map.get(:street_numbers, [])
      |> Enum.map(fn street_numbers ->
        filtered =
          Enum.filter(street_numbers, fn street_number ->
            Enum.member?(districts, street_number.geo_street.district)
          end)

        if Enum.count_until(filtered, 2) == 1 do
          filtered
        else
          nil
        end
      end)
      |> List.flatten()
      |> Enum.filter(fn item ->
        item != nil
      end)

    Map.merge(map, %{street_numbers: map.street_numbers ++ found_street_numbers})
  end

  defp guess_place(%{unclear: unclear} = map, districts) do
    found_places =
      Enum.map(Map.get(unclear, :places, []), fn places ->
        places
        |> do_filter_park_districts(districts)
        |> do_sort_places()
        |> Enum.take(1)
      end)
      |> List.flatten()
      |> Enum.filter(fn item ->
        item != nil
      end)

    Map.merge(map, %{places: map.places ++ found_places})
  end

  defp do_sort_places(places) do
    Enum.sort_by(places, fn place ->
      Enum.find_index(@place_sorting, fn item ->
        item == place.type
      end)
    end)
  end

  defp do_filter_park_districts(places, districts) do
    Enum.filter(places, fn place ->
      Enum.member?(districts, place.district)
    end)
  end

  defp clean_text(text) do
    text
    |> String.replace("Strasse", "Straße")
    |> String.replace("Str.", "Straße")
  end

  defp geo_map(map, items) do
    Enum.reduce(items, map, fn item, map ->
      if Map.has_key?(map, item.name) do
        Map.put(map, item.name, Map.get(map, item.name) ++ [item])
      else
        Map.put(map, item.name, [item])
      end
    end)
  end

  def add_streets(manager \\ __MODULE__, streets) do
    GenServer.call(manager, {:add_streets, streets})
  end

  def add_places(manager \\ __MODULE__, places) do
    GenServer.call(manager, {:add_places, places})
  end

  def analyze_text(manager \\ __MODULE__, text, options) do
    GenServer.call(manager, {:analyze_text, text, options})
  end
end
