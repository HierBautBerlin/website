defmodule Hierbautberlin.Services.QuartersTest do
  use ExUnit.Case, async: true

  alias Hierbautberlin.Services.Quarters

  test "parse/1" do
    assert Quarters.parse("2. Quartal 2018") == {2018, 2}
    assert Quarters.parse("vsl. 4. Quartal 2026") == {2026, 4}
    assert Quarters.parse("2026") == nil
    assert Quarters.parse(nil) == nil
  end

  test "first_day/1 and last_day/1" do
    assert Quarters.first_day({2018, 2}) |> DateTime.to_date() == ~D[2018-04-01]
    assert Quarters.last_day({2018, 2}) |> DateTime.to_date() == ~D[2018-06-30]
    assert Quarters.last_day({2020, 4}) |> DateTime.to_date() == ~D[2020-12-31]
    assert Quarters.first_day(nil) == nil
  end
end
