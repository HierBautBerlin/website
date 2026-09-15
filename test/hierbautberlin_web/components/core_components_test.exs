defmodule HierbautberlinWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import HierbautberlinWeb.CoreComponents

  describe "format_date/1" do
    test "formats timestamps in Berlin time" do
      # 1 January 2020, midnight in Berlin
      assert format_date(~U[2019-12-31 23:00:00Z]) == "01.01.2020"
      assert format_date(~N[2026-06-30 22:30:00]) == "01.07.2026"
      assert format_date(~D[2026-09-15]) == "15.09.2026"
      assert format_date(nil) == ""
    end
  end
end
