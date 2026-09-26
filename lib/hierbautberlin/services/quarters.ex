defmodule Hierbautberlin.Services.Quarters do
  @moduledoc """
  Quarters of a year as used by infraVelo: "2. Quartal 2018".
  """

  @doc """
  `{year, quarter}` of a text like "2. Quartal 2018", nil if there is none.
  """
  def parse(nil), do: nil

  def parse(text) do
    case Regex.named_captures(~r/(?<quarter>[1-4])\. Quartal (?<year>\d{4})/, text) do
      %{"year" => year, "quarter" => quarter} ->
        {String.to_integer(year), String.to_integer(quarter)}

      _ ->
        nil
    end
  end

  @doc """
  The first day of the quarter (midnight in Berlin).
  """
  def first_day(nil), do: nil

  def first_day({year, quarter}) do
    Date.new!(year, quarter * 3 - 2, 1) |> berlin_midnight()
  end

  @doc """
  The last day of the quarter (midnight in Berlin).
  """
  def last_day(nil), do: nil

  def last_day({year, quarter}) do
    Date.new!(year, quarter * 3, 1) |> Date.end_of_month() |> berlin_midnight()
  end

  defp berlin_midnight(date), do: DateTime.new!(date, ~T[00:00:00], "Europe/Berlin")
end
