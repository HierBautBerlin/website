defmodule Hierbautberlin.Importer.BerlinBaustellenTest do
  use Hierbautberlin.DataCase

  alias Hierbautberlin.GeoData.GeoItem
  alias Hierbautberlin.Importer.BerlinBaustellen

  # The fixture is the real layer, reduced to five entries with shortened
  # geometries: one rated 1 (skipped), a no parking zone without an end
  # (31.12.2099), two construction sites and the closure for the marathon.
  defmodule ImportMock do
    def get!(url, [], timeout: 60_000, recv_timeout: 300_000) do
      send(self(), {:request, url})
      %{body: features(), headers: [], status_code: 200}
    end

    def features, do: File.read!("./test/support/data/gdi/planb_ereignisse.json")
  end

  # The no parking zone is gone
  defmodule UpdateMock do
    def get!(_url, [], _opts) do
      json = Jason.decode!(ImportMock.features())

      features =
        Enum.reject(json["features"], &(&1["properties"]["strasse"] == "An der Wuhlheide"))

      %{body: Jason.encode!(%{json | "features" => features}), headers: [], status_code: 200}
    end
  end

  defmodule BrokenMock do
    def get!(_url, _headers, _opts), do: %{body: "", headers: [], status_code: 503}
  end

  describe "import/1" do
    test "imports the entries rated 2 and above" do
      {:ok, items} = BerlinBaustellen.import(ImportMock)

      assert_received {:request, url}
      assert url =~ "https://gdi.berlin.de/services/wfs/planb_ereignisse?"
      assert url =~ "TYPENAMES=planb_ereignisse%3Aereignisse"

      assert items |> Enum.map(& &1.title) |> Enum.sort() == [
               "An der Wuhlheide",
               "Badstraße 48–52",
               "Sewanstraße zwischen Huronseestraße und Mellenseestraße",
               "Straße des 17. Juni zwischen Yitzhak-Rabin-Straße und Platz des 18. März"
             ]

      badstrasse = items |> Enum.find(&(&1.title == "Badstraße 48–52")) |> Repo.preload(:source)

      assert badstrasse.subtitle == "Baustelle: Fahrstreifen-Reduzierung"

      assert badstrasse.description == """
             Ortsteil: Gesundbrunnen (Mitte)
             Einschränkung: Fahrstreifen-Reduzierung
             Zeitraum: 31.05.2021 bis 30.06.2027\
             """

      assert badstrasse.url == nil
      assert badstrasse.date_start == ~U[2021-05-30 22:00:00Z]
      assert badstrasse.date_end == ~U[2027-06-29 22:00:00Z]
      assert %Geo.MultiPolygon{srid: 4326} = badstrasse.geometry
      assert badstrasse.geo_point == nil
      assert badstrasse.importance == 1.5
      assert badstrasse.relevance_half_life == 14
      assert badstrasse.external_id =~ ~r/^planb:[0-9a-f]{16}$/
      assert badstrasse.source.short_name == "BERLIN_BAUSTELLEN"

      assert badstrasse.source.copyright ==
               "Geoportal Berlin / Planbare Ereignisse im öffentlichen Straßenland"

      # rated 2, "31.12.2099" is no end
      no_parking = items |> Enum.find(&(&1.title == "An der Wuhlheide"))
      assert no_parking.subtitle == "Sonstiges Ereignis: Haltverbote"
      assert no_parking.date_end == nil
      assert no_parking.state == "active"
      assert no_parking.importance == 1.0
      assert no_parking.description =~ "Zeitraum: ab 12.03.2020"

      marathon = items |> Enum.find(&String.starts_with?(&1.title, "Straße des 17. Juni"))
      assert marathon.subtitle == "Sonstiges Ereignis: Vollsperrung beider Fahrbahnen"
      assert marathon.description =~ "Zeitraum: 26.09.2026 bis 27.09.2026\n"
      assert marathon.description =~ "Aufbau ab: 19.09.2026\nAbbau bis: 30.09.2026"

      # "Sicherung gemäß Vz.-plan" is not part of the subtitle
      sewanstrasse = items |> Enum.find(&String.starts_with?(&1.title, "Sewanstraße"))
      assert sewanstrasse.subtitle == "Baustelle: Fahrstreifen-Reduzierung"
    end

    test "updates the items and hides the ones that are gone" do
      {:ok, first} = BerlinBaustellen.import(ImportMock)
      {:ok, second} = BerlinBaustellen.import(UpdateMock)

      assert length(second) == 3
      assert Enum.all?(second, fn item -> item.id in Enum.map(first, & &1.id) end)

      assert Repo.get_by!(GeoItem, title: "An der Wuhlheide").hidden
      assert Repo.aggregate(GeoItem, :count) == 4
    end

    test "returns an error when the service is down" do
      assert {:error, %RuntimeError{}} = BerlinBaustellen.import(BrokenMock)
    end
  end
end
