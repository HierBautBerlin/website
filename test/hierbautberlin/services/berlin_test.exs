defmodule Hierbautberlin.Services.BerlinTest do
  use Hierbautberlin.DataCase

  alias Hierbautberlin.Services.Berlin

  describe "find_districts/1" do
    test "it finds a district" do
      assert Berlin.find_districts("Hier in Friedrichshain-Kreuzberg") == [
               "Friedrichshain-Kreuzberg"
             ]
    end
  end
end
