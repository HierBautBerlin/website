defmodule Hierbautberlin.GeoData.AnalyzeText do
  require Logger
  use GenServer
  import Ecto.Query, warn: false

  alias Hierbautberlin.Repo
  alias Hierbautberlin.GeoData.{GeoStreet, GeoStreetNumber}

  def init(streets) when is_list(streets) do
    street_names = Enum.map(streets, & &1.name)

    {:ok,
     %{
       streets: street_map(%{}, streets),
       graph: AhoCorasick.new(street_names)
     }}
  end

  def init(_quizzes), do: {:error, "streets must be a list"}

  def start_link(options \\ []) do
    Logger.debug("Booting street analyzer")
    query = from(streets in GeoStreet)
    streets = Repo.all(query)
    Logger.debug("... with #{length(streets)} Streets")
    server = GenServer.start_link(__MODULE__, streets, options)
    Logger.debug("Booting street analyzer completed")
    server
  end

  def handle_call({:add_streets, streets}, _from, state) do
    Enum.each(streets, fn street ->
      AhoCorasick.add_term(state.graph, street.name)
    end)

    AhoCorasick.build_trie(state.graph)
    {:reply, :ok, Map.merge(state, %{streets: street_map(state.streets, streets)})}
  end

  def handle_call({:analyze_text, text, options}, _from, state) do
    options = Map.merge(%{districts: []}, options)

    text = clean_text(text)
    districts = options.districts

    result =
      state.graph
      |> AhoCorasick.search(text)
      |> MapSet.to_list()
      |> Enum.reduce(
        %{
          streets: [],
          street_numbers: [],
          places: [],
          unclear: %{}
        },
        fn {hit, start_pos, length}, acc ->
          number = text |> String.slice(start_pos + length, 10) |> get_street_number()

          if number do
            find_street_number_in(acc, state.streets[hit], number)
          else
            find_street_in(acc, state.streets[hit])
          end
        end
      )

    if Enum.empty?(result.unclear) do
      {:reply, Map.delete(result, :unclear), state}
    else
      relevant_districts = Enum.uniq(districts_for(result) ++ districts)

      {:reply,
       result
       |> guess_streets(relevant_districts)
       |> guess_street_numbers(relevant_districts)
       |> Map.delete(:unclear), state}
    end
  end

  defp districts_for(map) do
    street_districts = map.streets |> Enum.map(& &1.district)
    street_number_districts = map.street_numbers |> Enum.map(& &1.geo_street.district)

    Enum.uniq(street_districts ++ street_number_districts)
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

  defp clean_text(text) do
    text
    |> String.replace("Strasse", "Straße")
    |> String.replace("Str.", "Straße")
  end

  defp street_map(map, streets) do
    Enum.reduce(streets, map, fn street, map ->
      if Map.has_key?(map, street.name) do
        Map.put(map, street.name, Map.get(map, street.name) ++ [street])
      else
        Map.put(map, street.name, [street])
      end
    end)
  end

  @spec add_streets(atom | pid | {atom, any} | {:via, atom, any}, any) :: any
  def add_streets(manager \\ __MODULE__, streets) do
    GenServer.call(manager, {:add_streets, streets})
  end

  def analyze_text(manager \\ __MODULE__, text, options) do
    GenServer.call(manager, {:analyze_text, text, options})
  end
end
