defmodule Hierbautberlin.GeoData.ReanalyzeTest do
  use Hierbautberlin.DataCase, async: false

  alias Hierbautberlin.FileStorage
  alias Hierbautberlin.GeoData.{AnalyzeText, Reanalyze}
  alias Hierbautberlin.Importer.BerlinerAmtsblatt

  @amtsblatt "test/support/data/amtsblatt/abl_2021_28_2389_2480_online.pdf"

  defmodule ArticleMock do
    def get!(_url, _headers, _opts) do
      %{
        status_code: 200,
        headers: [],
        body: ~s(<div class="article" role="main"><p>Neue Bäume in der Liebigstraße</p></div>)
      }
    end
  end

  setup do
    on_exit(fn -> AnalyzeText.reset_index() end)
  end

  test "updates the links of press releases" do
    source = insert(:source, short_name: "BERLIN_PRESSE")
    old_street = insert(:street, name: "Rigaer Straße", district: "Friedrichshain-Kreuzberg")
    new_street = insert(:street, name: "Liebigstraße", district: "Friedrichshain-Kreuzberg")
    AnalyzeText.add_streets([old_street, new_street])

    news_item =
      insert(:news_item,
        source: source,
        title: "Bäume",
        content: "Neue Bäume",
        url: "https://www.berlin.de/ba-friedrichshain-kreuzberg/aktuelles/pressemitteilung.1.php",
        geo_streets: [old_street],
        geo_street_numbers: [],
        geo_places: []
      )

    assert %{items: 1, changed: 1, added: 1, removed: 1} =
             Reanalyze.run(source: "BERLIN_PRESSE", http_connection: ArticleMock, delay: 0)

    # dry run: nothing changed
    assert news_item
           |> Repo.reload!()
           |> Repo.preload(:geo_streets)
           |> Map.get(:geo_streets)
           |> Enum.map(& &1.id) == [old_street.id]

    Reanalyze.run(source: "BERLIN_PRESSE", http_connection: ArticleMock, delay: 0, dry_run: false)

    assert news_item
           |> Repo.reload!()
           |> Repo.preload(:geo_streets)
           |> Map.get(:geo_streets)
           |> Enum.map(& &1.id) == [new_street.id]
  end

  test "uses the stored text of news items" do
    source = insert(:source, short_name: "BERLIN_AMTSBLATT")
    street = insert(:street, name: "Liebigstraße", district: "Friedrichshain-Kreuzberg")
    AnalyzeText.add_streets([street])

    insert(:news_item,
      source: source,
      full_text: "Neue Bäume in der Liebigstraße",
      districts: ["Friedrichshain-Kreuzberg"],
      geo_streets: [],
      geo_street_numbers: [],
      geo_places: []
    )

    assert %{items: 1, changed: 1, added: 1, removed: 0, missing_text: 0} =
             Reanalyze.run(source: "BERLIN_AMTSBLATT")
  end

  test "a second run over an interpolated house number reports no changes" do
    source = insert(:source, short_name: "BERLIN_AMTSBLATT")
    street = insert(:street, name: "Margarete Steffin Straße", street_numbers: [], geometry: nil)

    insert(:street_number,
      number: "10",
      geo_street_id: street.id,
      geo_point: %Geo.Point{coordinates: {13.0, 52.0}, srid: 4326}
    )

    insert(:street_number,
      number: "20",
      geo_street_id: street.id,
      geo_point: %Geo.Point{coordinates: {13.1, 52.0}, srid: 4326}
    )

    AnalyzeText.add_streets([street])

    insert(:news_item,
      source: source,
      full_text: "Neue Bäume in der Margarete Steffin Straße 14",
      districts: [],
      geo_streets: [],
      geo_street_numbers: [],
      geo_places: []
    )

    # a dry run counts the interpolated number, which has no id yet, and stores nothing
    assert %{items: 1, changed: 1, added: 1, removed: 0} =
             Reanalyze.run(source: "BERLIN_AMTSBLATT")

    assert Repo.all(Hierbautberlin.GeoData.GeoStreetNumber) |> Enum.filter(& &1.interpolated) ==
             []

    assert %{items: 1, changed: 1, added: 1, removed: 0} =
             Reanalyze.run(source: "BERLIN_AMTSBLATT", dry_run: false)

    # the interpolated number is stored now, so nothing may look added or removed
    assert %{items: 1, changed: 0, added: 0, removed: 0} =
             Reanalyze.run(source: "BERLIN_AMTSBLATT", dry_run: false)

    numbers = Repo.all(Hierbautberlin.GeoData.GeoStreetNumber)
    assert length(Enum.filter(numbers, & &1.interpolated)) == 1
  end

  test "extracts the text of stored Amtsblatt PDFs, which have no outline" do
    source = insert(:source, short_name: "BERLIN_AMTSBLATT")
    street = insert(:street, name: "DigitalPakt Schule")
    AnalyzeText.add_streets([street])

    # the importer stores the PDFs shortened with qpdf, that removes the outline
    path = FileStorage.path_for_file("amtsblatt/#{Path.basename(@amtsblatt)}")
    File.mkdir_p!(Path.dirname(path))
    {_, 0} = System.cmd("qpdf", ["--empty", "--pages", @amtsblatt, "1-8", "--", path])
    on_exit(fn -> File.rm(path) end)
    assert BerlinerAmtsblatt.extract_items(path) == []

    news_items =
      for item <- BerlinerAmtsblatt.extract_items(@amtsblatt, 8) do
        insert(:news_item,
          source: source,
          external_id: item.url,
          title: item.title,
          geo_streets: [],
          geo_street_numbers: [],
          geo_places: []
        )
      end

    assert length(news_items) == 3

    assert %{items: 3, missing_text: 0, changed: 1, added: 1, removed: 0} =
             Reanalyze.run(source: "BERLIN_AMTSBLATT", dry_run: false)

    [first | _] = news_items = Enum.map(news_items, &Repo.reload!/1)
    first = Repo.preload(first, :geo_streets)
    assert Enum.map(first.geo_streets, & &1.name) == ["DigitalPakt Schule"]
    assert Enum.all?(news_items, & &1.full_text)
    assert first.full_text =~ "DigitalPakt Schule"

    # the second run uses the stored texts
    File.rm!(path)

    assert %{items: 3, missing_text: 0, changed: 0} =
             Reanalyze.run(source: "BERLIN_AMTSBLATT", dry_run: false)
  end
end
