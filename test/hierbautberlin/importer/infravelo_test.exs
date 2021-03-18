defmodule Hierbautberlin.Importer.InfraveloTest do
  use Hierbautberlin.DataCase

  alias Hierbautberlin.Importer.Infravelo
  alias Hierbautberlin.ImportMock

  test "basic import of infravelo data" do
    Infravelo.import(ImportMock)
  end
end
