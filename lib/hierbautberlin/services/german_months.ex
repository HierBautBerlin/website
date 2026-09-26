defmodule Hierbautberlin.Services.GermanMonths do
  @moduledoc """
  The German month names, for parsing dates like "3. September 2026".
  """

  @names ~w(Januar Februar März April Mai Juni Juli August September Oktober November Dezember)

  def names, do: @names

  @doc """
  The names as alternatives for a regex: "Januar|Februar|...". Add the `i` flag
  to the regex to find them in any case.
  """
  def pattern, do: Enum.join(@names, "|")

  @doc """
  The number of the month (1 to 12), in any case. `nil` for an unknown name.
  """
  def number(name) do
    name = String.downcase(to_string(name))

    case Enum.find_index(@names, &(String.downcase(&1) == name)) do
      nil -> nil
      index -> index + 1
    end
  end
end
