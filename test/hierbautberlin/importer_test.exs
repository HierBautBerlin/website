defmodule Hierbautberlin.ImporterTest do
  use Hierbautberlin.DataCase, async: false

  import ExUnit.CaptureLog

  alias Hierbautberlin.Importer

  test "runs all importers even if one fails, crashes or hangs" do
    log =
      capture_log(fn ->
        results =
          Importer.run_importers(
            [
              {"ok", fn -> {:ok, [1, 2, 3]} end},
              {"error", fn -> {:error, %RuntimeError{message: "broken"}} end},
              {"crash", fn -> raise "boom" end},
              {"hang", fn -> Process.sleep(:infinity) end},
              {"after", fn -> {:ok, [1]} end}
            ],
            200
          )

        assert [
                 {"ok", {:ok, 3}},
                 {"error", {:error, %RuntimeError{message: "broken"}}},
                 {"crash", {:error, {:exit, _}}},
                 {"hang", {:error, :timeout}},
                 {"after", {:ok, 1}}
               ] = results
      end)

    assert log =~ "Importer hang failed"
  end
end
