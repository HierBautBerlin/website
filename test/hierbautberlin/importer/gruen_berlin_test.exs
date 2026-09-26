defmodule Hierbautberlin.Importer.GruenBerlinTest do
  use Hierbautberlin.DataCase

  alias Hierbautberlin.GeoData
  alias Hierbautberlin.Importer.GruenBerlin

  # The fixtures are the real pages with the inline logos removed. The list pages
  # only kept the entries the test needs: two press releases and one infraVelo
  # entry (page 1) and a release that redirects to the website of its project
  # (page 2).
  defmodule ImportMock do
    @pages %{
      "https://gruen-berlin.de/presse/pressemitteilungen" => "list_page1.html",
      "https://gruen-berlin.de/presse/pressemitteilungen?tx_news_pi1%5Bcontroller%5D=News&tx_news_pi1%5Bpage%5D=2&cHash=489ee30c55e4d429e2af3593a5a5e4d4" =>
        "list_page2.html",
      "https://gruen-berlin.de/pressemitteilung/bauarbeiten-fuer-neuen-spielbereich-am-rathaus-und-marx-engels-forum-starten" =>
        "spielbereich.html",
      "https://gruen-berlin.de/pressemitteilung/mauerpark-falkplatz-fertiggestellt" =>
        "mauerpark_falkplatz.html",
      "https://gruen-berlin.de/pressemitteilung/sommertagstraum" => "sommertagstraum.html"
    }

    def get!(url, ["User-Agent": "hierbautberlin.de"], timeout: 60_000, recv_timeout: 60_000) do
      case @pages[url] do
        nil ->
          %{body: "", headers: [], status_code: 404}

        file ->
          %{
            body: File.read!("./test/support/data/gruen_berlin/#{file}"),
            headers: [],
            status_code: 200
          }
      end
    end
  end

  setup do
    # the index is global, without a reset the streets of the other tests of
    # this file are still in it (and make every name ambiguous)
    GeoData.AnalyzeText.reset_index()
    on_exit(fn -> GeoData.AnalyzeText.reset_index() end)

    rathausstrasse = insert(:street, name: "Rathausstraße", district: "Mitte", street_numbers: [])
    spandauer = insert(:street, name: "Spandauer Straße", district: "Mitte", street_numbers: [])

    mauerpark = insert(:place, name: "Mauerpark", district: "Pankow", type: "Park")

    GeoData.AnalyzeText.add_streets([rathausstrasse, spandauer])
    GeoData.AnalyzeText.add_places([mauerpark])

    %{
      rathausstrasse: rathausstrasse,
      spandauer: spandauer,
      mauerpark: mauerpark
    }
  end

  describe "import/2" do
    test "imports the press releases of the list pages", context do
      {:ok, [spielbereich, mauerpark, sommertagstraum]} = GruenBerlin.import(ImportMock, pages: 2)

      spielbereich = Repo.preload(spielbereich, :source)

      assert spielbereich.title ==
               "Bauarbeiten für neuen Spielbereich am Rathaus- und Marx-Engels-Forum starten"

      assert spielbereich.url ==
               "https://gruen-berlin.de/pressemitteilung/bauarbeiten-fuer-neuen-spielbereich-am-rathaus-und-marx-engels-forum-starten"

      assert spielbereich.external_id == spielbereich.url
      assert spielbereich.published_at == ~U[2026-09-02 22:00:00Z]
      assert spielbereich.source.name == "Grün Berlin"
      assert spielbereich.source.short_name == "GRUEN_BERLIN"

      # the bullet points and the first paragraph are the teaser
      assert spielbereich.content =~
               "* Mehr Raum für Kinder und Familien: Spielelemente greifen Kugelform des Fernsehturms auf"

      assert spielbereich.content =~ "Heute, am 3. September 2026, starten die Baumaßnahmen"
      refute spielbereich.content =~ "Inklusives Spielplatzkonzept"

      # the whole article is analyzed
      assert spielbereich.full_text =~ "Inklusives Spielplatzkonzept"
      refute spielbereich.full_text =~ "Kontakt Pressestelle"

      assert spielbereich.geo_streets |> Enum.map(& &1.id) |> Enum.sort() ==
               Enum.sort([context.rathausstrasse.id, context.spandauer.id])

      # the project of a release names the place it is about
      mauerpark_item = Repo.preload(mauerpark, :source)
      assert mauerpark_item.title == "Mauerpark: Falkplatz fertiggestellt"
      assert mauerpark_item.published_at == ~U[2026-06-03 22:00:00Z]
      assert mauerpark_item.geo_places |> Enum.map(& &1.id) == [context.mauerpark.id]
      assert mauerpark_item.geo_points.coordinates == [{13.2679, 52.51}]

      # a release that redirects to the website of its project has no article
      # here, it is imported with its title and its project
      assert sommertagstraum.title == "SommerTagsTraum"
      assert sommertagstraum.url == "https://gruen-berlin.de/pressemitteilung/sommertagstraum"
      assert sommertagstraum.content == nil
      assert sommertagstraum.full_text == "SommerTagsTraum\nNatur Park Südgelände"
    end

    test "skips the releases of infraVelo, their projects are imported from infravelo.de" do
      {:ok, items} = GruenBerlin.import(ImportMock, pages: 1)

      titles = Enum.map(items, & &1.title)
      assert length(titles) == 2
      refute "Geschützte Radfahrstreifen für die Schönhauser Allee" in titles
    end

    test "does not fetch the articles of releases that are stored with their text" do
      {:ok, items} = GruenBerlin.import(ImportMock, pages: 2)
      assert length(items) == 3

      # the release that redirects has no text of its own, it is read again
      {:ok, again} = GruenBerlin.import(ImportMock, pages: 2)
      assert Enum.map(again, & &1.title) == ["SommerTagsTraum"]

      {:ok, all} = GruenBerlin.import(ImportMock, pages: 2, skip_imported: false)
      assert length(all) == 3
      assert Repo.aggregate(GeoData.NewsItem, :count) == 3
    end
  end

  describe "parse_list/1" do
    test "reads title, project and date of every entry that is not skipped" do
      document =
        "./test/support/data/gruen_berlin/list_page1.html"
        |> File.read!()
        |> Floki.parse_document!()

      assert GruenBerlin.parse_list(document) |> Enum.map(&{&1.projects, &1.published_at}) == [
               {["Rathaus- und Marx-Engels-Forum"], ~U[2026-09-02 22:00:00Z]},
               {["Mauerpark"], ~U[2026-06-03 22:00:00Z]}
             ]
    end
  end
end
