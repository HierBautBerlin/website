defmodule Hierbautberlin.Importer.StepWohnenTest do
  use Hierbautberlin.DataCase

  alias Hierbautberlin.Importer.StepWohnen

  # The fixtures are the real layers, reduced to a few sites and districts with
  # shortened geometries. The site "Blankenburger Süden" is a district, too.
  defmodule ImportMock do
    @files %{
      "h_step_wo_2040_wobau_fertig" => "step_wohnen_sites.json",
      "i_step_wo_2040_wobau_gemeinw" => "step_wohnen_public_interest.json",
      "j_step_wo_2040_neustadtquar" => "step_wohnen_districts.json"
    }

    def get!(url, [], timeout: 60_000, recv_timeout: 300_000) do
      %{"TYPENAMES" => "step_wo_2040:" <> layer} = URI.decode_query(URI.parse(url).query)

      %{
        body: File.read!("./test/support/data/gdi/#{Map.fetch!(@files, layer)}"),
        headers: [],
        status_code: 200
      }
    end
  end

  describe "import/1" do
    test "imports the districts and the sites" do
      {:ok, items} = StepWohnen.import(ImportMock)

      assert items |> Enum.map(& &1.external_id) |> Enum.sort() == [
               "district:S01",
               "district:S03",
               "district:S04",
               "district:S15",
               "site:S1",
               "site:S10",
               "site:S100"
             ]

      blankenburg =
        items |> Enum.find(&(&1.external_id == "district:S01")) |> Repo.preload(:source)

      assert blankenburg.title == "Blankenburger Süden"
      assert blankenburg.subtitle == "Neues Stadtquartier"
      assert blankenburg.state == "in_planning"

      assert blankenburg.url ==
               "https://www.berlin.de/sen/stadtentwicklung/neue-stadtquartiere/blankenburger-sueden/"

      # the number of flats and the completion come from the site
      assert blankenburg.description == """
             Aus dem Stadtentwicklungsplan Wohnen 2040.
             Angestrebter Baubeginn: 2027 - 2031
             Wohneinheiten: 2000 und mehr Wohneinheiten
             Fertigstellung: langfristig (2032 bis 2040)
             Gemeinwohlorientierung: Potenziale für gemeinwohlorientierten Wohnungsbau\
             """

      # the area is a symbol (a circle), the point of the site is used
      assert blankenburg.geometry == nil
      assert blankenburg.geo_point == %Geo.Point{coordinates: {13.454251, 52.579536}, srid: 4326}
      assert blankenburg.date_start == nil
      assert blankenburg.relevant_from == ~U[2026-12-31 23:00:00Z]
      assert blankenburg.relevant_until == ~U[2031-12-30 23:00:00Z]
      assert blankenburg.importance == 1.5
      assert blankenburg.source.short_name == "STEP_WOHNEN"

      # no site, the center of the circle
      buckower_felder = items |> Enum.find(&(&1.external_id == "district:S03"))
      assert buckower_felder.geometry == nil
      assert %Geo.Point{coordinates: {lng, lat}, srid: 4326} = buckower_felder.geo_point
      assert_in_delta lng, 13.419, 0.01
      assert_in_delta lat, 52.415, 0.01
      assert buckower_felder.state == "under_construction"
      assert buckower_felder.description =~ "Angestrebter Baubeginn: hat begonnen (im Bau)"

      europacity = items |> Enum.find(&(&1.external_id == "district:S04"))
      assert europacity.state == "finished"
      assert europacity.url == nil
      assert europacity.relevant_from == nil

      steinstrasse = items |> Enum.find(&(&1.external_id == "site:S1"))
      assert steinstrasse.title == "Steinstraße / Bahnhofstraße"
      assert steinstrasse.subtitle == "Wohnungsbau, 200 - 499 Wohneinheiten"
      assert steinstrasse.state == "under_construction"
      assert steinstrasse.importance == 1.5
      assert %Geo.Point{srid: 4326} = steinstrasse.geo_point
      assert steinstrasse.relevant_until == ~U[2026-12-30 23:00:00Z]

      assert steinstrasse.description =~
               "Gemeinwohlorientierung: Potenziale für gemeinwohlorientierten Wohnungsbau"

      falkenberger_chaussee = items |> Enum.find(&(&1.external_id == "site:S100"))
      assert falkenberger_chaussee.state == "intended"
      assert falkenberger_chaussee.description =~ "Fertigstellung: langfristig (2032 bis 2040)"
      assert falkenberger_chaussee.relevant_from == ~U[2031-12-31 23:00:00Z]
    end
  end
end
