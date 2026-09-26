defmodule Hierbautberlin.Importer.VIZTest do
  use Hierbautberlin.DataCase

  alias Hierbautberlin.GeoData
  alias Hierbautberlin.Importer.VIZ

  # The fixture is the real feed, reduced to three entries: the recurring
  # "Verkehrsvorschau" that has to be skipped and two messages.
  defmodule ImportMock do
    def get!(
          "https://viz.berlin.de/feed/",
          ["User-Agent": "hierbautberlin.de"],
          timeout: 60_000,
          recv_timeout: 60_000
        ) do
      %{body: File.read!("./test/support/data/viz/feed.json"), headers: [], status_code: 200}
    end
  end

  setup do
    # the index is global, without a reset the streets of the other tests of
    # this file are still in it (and make every name ambiguous)
    GeoData.AnalyzeText.reset_index()
    on_exit(fn -> GeoData.AnalyzeText.reset_index() end)

    haemmerling =
      insert(:street, name: "Hämmerlingstraße", district: "Treptow-Köpenick", street_numbers: [])

    bahnhofstrasse =
      insert(:street, name: "Bahnhofstraße", district: "Treptow-Köpenick", street_numbers: [])

    behmstrasse = insert(:street, name: "Behmstraße", district: "Pankow", street_numbers: [])

    GeoData.AnalyzeText.add_streets([haemmerling, bahnhofstrasse, behmstrasse])

    %{haemmerling: haemmerling, bahnhofstrasse: bahnhofstrasse, behmstrasse: behmstrasse}
  end

  describe "import/1" do
    test "imports the messages of the feed", context do
      {:ok, [behmstrasse, haemmerling]} = VIZ.import(ImportMock)

      behmstrasse = Repo.preload(behmstrasse, :source)

      assert behmstrasse.title ==
               "Markierungsarbeiten für sicheren Radweg am BSR-Recyclinghof in der Behmstraße beginnen 28.09.26"

      assert behmstrasse.url ==
               "https://viz.berlin.de/aktuelle-meldungen/markierungsarbeiten-fur-sicheren-radweg-am-bsr-recyclinghof-in-der-behmstrasse-beginnen/"

      assert behmstrasse.external_id == behmstrasse.url
      # 16:09 Berlin time, the minutes of the feed are the month
      assert behmstrasse.published_at == ~U[2026-09-24 14:09:00Z]
      assert behmstrasse.source.name == "Verkehrsinformationszentrale Berlin"
      assert behmstrasse.source.short_name == "VIZ"

      # the excerpt of the feed is the teaser and the analyzed text
      assert behmstrasse.content =~ "werden voraussichtlich ab 28. September 2026"
      assert behmstrasse.full_text == "#{behmstrasse.title}\n#{behmstrasse.content}"
      assert behmstrasse.geo_streets |> Enum.map(& &1.id) == [context.behmstrasse.id]

      assert haemmerling.published_at == ~U[2026-09-15 14:09:00Z]
      assert haemmerling.content =~ "Wie die Deutsche Bahn AG berichtet"

      assert haemmerling.geo_streets |> Enum.map(& &1.id) |> Enum.sort() ==
               Enum.sort([context.haemmerling.id, context.bahnhofstrasse.id])

      # the same messages again don't become new items
      {:ok, again} = VIZ.import(ImportMock)
      assert length(again) == 2
      assert Repo.aggregate(GeoData.NewsItem, :count) == 2
    end

    test "skips the recurring Verkehrsvorschau" do
      {:ok, items} = VIZ.import(ImportMock)

      titles = Enum.map(items, & &1.title)
      assert length(titles) == 2
      refute Enum.any?(titles, &String.contains?(&1, "Verkehrsvorschau"))
    end
  end

  describe "parse_feed/1" do
    test "leaves out entries without a title, url or date" do
      feed =
        Jason.encode!([
          %{title: "Ohne Datum", url: "https://viz.berlin.de/aktuelle-meldungen/ohne-datum/"},
          %{title: "Ohne Url", date: "2026-09-25T15:09:00"},
          %{
            title: "",
            url: "https://viz.berlin.de/aktuelle-meldungen/leer/",
            date: "2026-09-25T15:09:00"
          },
          %{
            title: "Vollsperrung",
            url: "https://viz.berlin.de/aktuelle-meldungen/vollsperrung/",
            date: "2026-09-25T15:09:00",
            excerpt: "Die Straße ist gesperrt."
          }
        ])

      assert VIZ.parse_feed(feed) == [
               %{
                 title: "Vollsperrung",
                 url: "https://viz.berlin.de/aktuelle-meldungen/vollsperrung/",
                 published_at: ~U[2026-09-25 13:09:00Z],
                 excerpt: "Die Straße ist gesperrt."
               }
             ]
    end

    test "returns nothing when the feed could not be read" do
      assert VIZ.parse_feed(nil) == []
    end
  end
end
