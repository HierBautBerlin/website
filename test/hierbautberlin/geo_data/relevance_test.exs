defmodule Hierbautberlin.GeoData.RelevanceTest do
  use Hierbautberlin.DataCase, async: true

  alias Hierbautberlin.GeoData.Relevance

  @published ~U[2026-09-01 10:00:00Z]

  describe "latest_date/2" do
    test "finds dates after the publication" do
      assert Relevance.latest_date("Sitzung am 14.09.2026 und am 3. Oktober 2026", @published) ==
               ~U[2026-10-03 23:59:59Z]
    end

    test "ignores dates before the publication and more than a year later" do
      text = "Bekanntmachung vom 25. August 2026 zum Gesetz vom 22. Juli 2003, fertig am 1.1.2030"
      assert Relevance.latest_date(text, @published) == nil
    end

    test "prefers deadlines and ignores start dates" do
      text =
        "Listung gilt ab 02.08.2027. Die Dokumente liegen vom 21. September bis einschließlich 23. Oktober 2026 aus. Sitzung am 12. November 2026."

      assert Relevance.latest_date(text, @published) == ~U[2026-10-23 23:59:59Z]
    end

    test "understands months and relative deadlines" do
      assert Relevance.latest_date("Die Bauarbeiten dauern bis Ende Oktober 2026.", @published) ==
               ~U[2026-10-31 23:59:59Z]

      assert Relevance.latest_date(
               "Einwendungen können innerhalb von drei Monaten erhoben werden.",
               @published
             ) == ~U[2026-12-01 23:59:59Z]
    end
  end

  describe "for_news_item/3" do
    test "participation with a deadline is most important until the deadline" do
      assert %{importance: 3.0, relevant_until: ~U[2026-10-02 23:59:59Z], relevance_half_life: 7} =
               Relevance.for_news_item(
                 "Öffentliche Auslegung eines Bebauungsplanentwurfs",
                 "Der Entwurf wird vom 1. September bis 2. Oktober 2026 öffentlich ausgelegt.",
                 @published
               )
    end

    test "events are relevant until they take place" do
      assert %{importance: 1.5, relevant_until: ~U[2026-09-12 23:59:59Z], relevance_half_life: 3} =
               Relevance.for_news_item(
                 "Kiezfest am Leon-Jessel-Platz",
                 "Das Bezirksamt lädt alle Nachbarn am 12. September 2026 ein.",
                 @published
               )
    end

    test "construction and closures are notable" do
      assert %{importance: 1.5, relevant_until: ~U[2026-09-15 10:00:00Z]} =
               Relevance.for_news_item("Umgestaltung des Metzer Platzes beginnt", "", @published)
    end

    test "administrative details are minor" do
      assert %{importance: 0.3} =
               Relevance.for_news_item(
                 "Grundstücksnummerierungen",
                 "Berliner Straße 12",
                 @published
               )
    end

    test "other news are relevant for two weeks" do
      assert %{
               importance: 1.0,
               relevant_from: @published,
               relevant_until: ~U[2026-09-15 10:00:00Z],
               relevance_half_life: 30
             } = Relevance.for_news_item("Neue Regenbogenbank im Park", "Eine Bank.", @published)
    end
  end

  describe "for_geo_item/1" do
    test "uses the dates of the item" do
      assert %{
               importance: 1.0,
               relevant_from: ~U[2026-01-01 00:00:00Z],
               relevant_until: ~U[2026-12-31 00:00:00Z],
               relevance_half_life: 180
             } =
               Relevance.for_geo_item(%{
                 date_start: ~U[2026-01-01 00:00:00Z],
                 date_end: ~U[2026-12-31 00:00:00Z]
               })
    end

    test "open participation is important and values of the importer win" do
      assert %{importance: 3.0, relevance_half_life: 14} =
               Relevance.for_geo_item(%{participation_open: true})

      assert %{importance: 0.3, relevant_until: nil} =
               Relevance.for_geo_item(%{importance: 0.3})
    end
  end
end
