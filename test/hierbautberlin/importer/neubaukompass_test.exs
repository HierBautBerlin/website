defmodule Hierbautberlin.Importer.NeubaukompassTest do
  use Hierbautberlin.DataCase

  alias Hierbautberlin.GeoData
  alias Hierbautberlin.Importer.Neubaukompass

  # The fixtures are real pages, reduced to a few projects: two pages of
  # apartments to buy (with a project in Kleinmachnow that has to be skipped and
  # one without coordinates), houses to buy (a project of the first listing
  # again), no apartments to rent and one house to rent.
  defmodule ImportMock do
    @listing "https://www.neubaukompass.de/neubau-immobilien/berlin-region/"
    @files %{
      "#{@listing}wohnung-kaufen/?pagenumber=1" => "wohnung_kaufen_1.html",
      "#{@listing}wohnung-kaufen/?pagenumber=2" => "wohnung_kaufen_2.html",
      "#{@listing}haus-kaufen/?pagenumber=1" => "haus_kaufen.html",
      "#{@listing}wohnung-mieten/?pagenumber=1" => "wohnung_mieten.html",
      "#{@listing}haus-mieten/?pagenumber=1" => "haus_mieten.html",
      "https://www.neubaukompass.de/neubau/siemensstrasse-berlin/149483.html" =>
        "project_149483.html"
    }

    def get!(url, ["User-Agent": "hierbautberlin.de"], timeout: 60_000, recv_timeout: 60_000) do
      send(self(), {:request, url})

      case Map.fetch(@files, url) do
        {:ok, file} ->
          %{
            body: File.read!("./test/support/data/neubaukompass/#{file}"),
            headers: [],
            status_code: 200
          }

        :error ->
          %{body: "", headers: [], status_code: 404}
      end
    end
  end

  defmodule BrokenMock do
    def get!(_url, _headers, _opts), do: %{body: "", headers: [], status_code: 503}
  end

  describe "import/2" do
    test "imports the projects in Berlin" do
      {:ok, items} = Neubaukompass.import(ImportMock, delay: 0)

      assert items |> Enum.map(& &1.external_id) |> Enum.sort() ==
               ["127686", "149483", "150686", "151554"]

      baumschulenstrasse = items |> Enum.find(&(&1.external_id == "127686"))
      baumschulenstrasse = Repo.preload(baumschulenstrasse, :source)

      assert baumschulenstrasse.title == "Baumschulenstraße 27/29"
      assert baumschulenstrasse.subtitle == "ESCON GmbH"

      assert baumschulenstrasse.url ==
               "https://www.neubaukompass.de/neubau/baumschulenstrasse-27-29-berlin/127686.html"

      assert baumschulenstrasse.geo_point == %Geo.Point{
               coordinates: {13.48634, 52.46454},
               srid: 4326
             }

      assert baumschulenstrasse.description ==
               """
               Sanierter Altbau in zentraler Lage mit klimatisierten Dachgeschosswohnungen
               Baumschulenstraße 27/29, 12437 Berlin
               1 - 4 Zimmer, 23 Wohneinheiten in Berlin - Baumschulenweg (Treptow)
               Preis: 222.500 - 741.000 €
               Fertigstellung: 07/2026\
               """

      # "07/2026" is over
      assert baumschulenstrasse.state == "finished"
      assert baumschulenstrasse.date_start == nil
      assert baumschulenstrasse.date_end == ~U[2026-07-31 00:00:00Z]
      assert baumschulenstrasse.date_updated == ~U[2026-08-31 09:02:49Z]
      assert baumschulenstrasse.relevant_from == ~U[2024-11-22 18:41:06Z]
      assert baumschulenstrasse.relevant_until == ~U[2026-07-31 00:00:00Z]
      assert baumschulenstrasse.source.short_name == "NEUBAUKOMPASS"
      assert baumschulenstrasse.source.name == "Neubaukompass"

      kiezgen = items |> Enum.find(&(&1.external_id == "150686"))
      assert kiezgen.title == "Det Kiezgen"
      assert kiezgen.state == "under_construction"
      assert kiezgen.date_end == ~U[2028-12-31 00:00:00Z]

      rental = items |> Enum.find(&(&1.external_id == "151554"))

      assert rental.url ==
               "https://www.neubaukompass.de/neubau-mieten/hygge-hoefe-berlin/151554.html"

      assert rental.description =~ "Miete: 999 - 2.948 €"
      assert rental.state == "finished"
      assert rental.date_end == nil
    end

    test "reads the coordinates of a project without an address from its page" do
      {:ok, items} = Neubaukompass.import(ImportMock, delay: 0)

      siemensstrasse = items |> Enum.find(&(&1.external_id == "149483"))
      assert siemensstrasse.title == "Siemensstraße"
      assert siemensstrasse.geo_point == %Geo.Point{coordinates: {13.33292, 52.53269}, srid: 4326}
      assert siemensstrasse.date_end == ~U[2027-03-31 00:00:00Z]

      project_page = "https://www.neubaukompass.de/neubau/siemensstrasse-berlin/149483.html"
      assert_received {:request, ^project_page}

      # the next import doesn't read the project page again
      {:ok, again} = Neubaukompass.import(ImportMock, delay: 0)
      refute_received {:request, ^project_page}

      assert again |> Enum.find(&(&1.external_id == "149483")) |> Map.get(:geo_point) ==
               siemensstrasse.geo_point

      assert Repo.aggregate(GeoData.GeoItem, :count) == 4
    end

    test "hides projects that are not listed anymore and shows them again" do
      {:ok, source} =
        GeoData.upsert_source(%{
          short_name: "NEUBAUKOMPASS",
          name: "Neubaukompass",
          url: "https://www.neubaukompass.de/",
          copyright: "Neubaukompass"
        })

      {:ok, gone} =
        GeoData.upsert_geo_item(%{source_id: source.id, external_id: "1", title: "Verkauft"})

      {:ok, back} =
        GeoData.upsert_geo_item(%{
          source_id: source.id,
          external_id: "150686",
          title: "Det Kiezgen",
          hidden: true
        })

      {:ok, _items} = Neubaukompass.import(ImportMock, delay: 0)

      assert Repo.reload(gone).hidden
      refute Repo.reload(back).hidden
    end

    test "fails without hiding anything when a listing can't be read" do
      assert {:error, %RuntimeError{}} = Neubaukompass.import(BrokenMock, delay: 0)
    end
  end

  describe "parse_listing/1" do
    test "returns the projects and the number of pages" do
      {projects, pages} =
        "./test/support/data/neubaukompass/wohnung_kaufen_1.html"
        |> File.read!()
        |> Neubaukompass.parse_listing()

      assert pages == 2
      assert Enum.map(projects, & &1.external_id) == ["127686", "137952", "149483"]
    end

    test "returns nothing for a page without projects" do
      assert Neubaukompass.parse_listing("<html><body></body></html>") == {[], 0}
    end
  end

  describe "parse_ready_at/1" do
    test "returns the end of the given month, quarter or year" do
      assert Neubaukompass.parse_ready_at("07/2026") == ~U[2026-07-31 00:00:00Z]
      assert Neubaukompass.parse_ready_at("01.09.2026") == ~U[2026-09-30 00:00:00Z]
      assert Neubaukompass.parse_ready_at("Q4 2028") == ~U[2028-12-31 00:00:00Z]
      assert Neubaukompass.parse_ready_at("Q3/2026") == ~U[2026-09-30 00:00:00Z]
      assert Neubaukompass.parse_ready_at("Q2/Q3 2027") == ~U[2027-09-30 00:00:00Z]
      assert Neubaukompass.parse_ready_at("Q'4 2025 / Q'1 2026") == ~U[2026-03-31 00:00:00Z]
      assert Neubaukompass.parse_ready_at("1. Quartal 2027") == ~U[2027-03-31 00:00:00Z]
      assert Neubaukompass.parse_ready_at("vsl. ab Februar 2028") == ~U[2028-02-29 00:00:00Z]
      assert Neubaukompass.parse_ready_at("März 2027") == ~U[2027-03-31 00:00:00Z]
      assert Neubaukompass.parse_ready_at("Herbst 2026") == ~U[2026-11-30 00:00:00Z]
      assert Neubaukompass.parse_ready_at("vsl. Mitte 2027") == ~U[2027-06-30 00:00:00Z]
      assert Neubaukompass.parse_ready_at("Vsl. Ende 2027") == ~U[2027-12-31 00:00:00Z]
      assert Neubaukompass.parse_ready_at("2027") == ~U[2027-12-31 00:00:00Z]
    end

    test "returns nil without a year" do
      assert Neubaukompass.parse_ready_at("sofort") == nil
      assert Neubaukompass.parse_ready_at("Auf Anfrage") == nil
      assert Neubaukompass.parse_ready_at(nil) == nil
    end
  end
end
