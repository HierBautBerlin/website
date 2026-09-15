defmodule Hierbautberlin.Importer.BerlinerAmtsblattTest do
  use Hierbautberlin.DataCase

  @import_path Path.join(Application.compile_env(:hierbautberlin, :import_path), "amtsblatt")

  alias Hierbautberlin.FileStorage
  alias Hierbautberlin.GeoData.AnalyzeText
  alias Hierbautberlin.Importer.BerlinerAmtsblatt

  defmodule EmptyImportMock do
    def get!(
          "https://www.berlin.de/landesverwaltungsamt/logistikservice/amtsblatt-fuer-berlin/",
          ["User-Agent": "hierbautberlin.de"],
          timeout: 60_000,
          recv_timeout: 60_000
        ) do
      %{body: "<html></html>", headers: [], status_code: 200}
    end
  end

  defmodule ImportMock do
    def get!(
          "https://www.berlin.de/landesverwaltungsamt/logistikservice/amtsblatt-fuer-berlin/",
          ["User-Agent": "hierbautberlin.de"],
          timeout: 60_000,
          recv_timeout: 60_000
        ) do
      {:ok, html} = File.read("test/support/data/amtsblatt/index_page_single.html")
      %{body: html, headers: [], status_code: 200}
    end
  end

  defmodule DownloadMock do
    def get(
          "https://www.berlin.de/landesverwaltungsamt/_assets/logistikservice/amtsblatt-fuer-berlin/abl_2021_28_2389_2480_online.pdf",
          file
        ) do
      content = File.read!("test/support/data/amtsblatt/abl_2021_28_2389_2480_online.pdf")
      IO.binwrite(file, content)
    end
  end

  defmodule BrokenDownloadMock do
    def get(_url, file), do: IO.binwrite(file, "<html>Not found</html>")
  end

  setup do
    clean_storage()

    :ok
  end

  def clean_storage() do
    "amtsblatt/abl_2021_28_2389_2480_online.pdf"
    |> FileStorage.path_for_file()
    |> File.rm()

    File.mkdir_p(@import_path)
    File.rm_rf(Path.join(@import_path, "*"))
  end

  describe "import/1" do
    test "checks the import folder and parses all files in it" do
      File.cp(
        "test/support/data/amtsblatt/abl_2021_28_2389_2480_online.pdf",
        Path.join(@import_path, "abl_2021_28_2389_2480_online.pdf")
      )

      {:ok, news_items} = Hierbautberlin.Importer.BerlinerAmtsblatt.import(EmptyImportMock)

      assert length(news_items) == 28

      titles = Enum.map(news_items, & &1.title)

      refute Enum.member?(titles, "Beitragsordnung")
      refute Enum.member?(titles, "Gebührenordnung")

      refute File.exists?(Path.join(@import_path, "abl_2021_28_2389_2480_online.pdf"))
      assert FileStorage.exists?("amtsblatt/abl_2021_28_2389_2480_online.pdf")

      clean_storage()
    end

    test "downloads a pdf file and parses it" do
      {:ok, news_items} =
        Hierbautberlin.Importer.BerlinerAmtsblatt.import(ImportMock, DownloadMock)

      assert length(news_items) == 28

      first = List.first(news_items)

      assert first.title ==
               "Förderbekanntmachung landesweiter Maßnahmen im Land Berlin zum DigitalPakt Schule 2019 bis 2024"

      assert first.url ==
               "/view_pdf/amtsblatt/abl_2021_28_2389_2480_online.pdf?page=4&title=F%C3%B6rderbekanntmachung+landesweiter+Ma%C3%9Fnahmen+im+Land+Berlin+zum+DigitalPakt+Schule+2019+bis+2024"

      last = List.last(news_items)

      assert last.title ==
               "Widmung einer öffentlichen Grün- und Erholungsanlage"

      assert last.url ==
               "/view_pdf/amtsblatt/abl_2021_28_2389_2480_online.pdf?page=61&title=Widmung+einer+%C3%B6ffentlichen+Gr%C3%BCn-+und+Erholungsanlage"

      assert FileStorage.exists?("amtsblatt/abl_2021_28_2389_2480_online.pdf")

      file = FileStorage.get_file_by_name!("amtsblatt/abl_2021_28_2389_2480_online.pdf")
      assert file.title == "Amtsblatt für Berlin, 71. Jahrgang Nr. 28"

      filename = FileStorage.path_for_file(file)

      assert BerlinerAmtsblatt.get_number_of_pages(filename) == 61

      clean_storage()
    end
  end

  describe "find_download_urls/1" do
    test "finds the pdfs in the current page layout" do
      urls =
        "test/support/data/amtsblatt/index_page_2026.html"
        |> File.read!()
        |> BerlinerAmtsblatt.find_download_urls()

      assert length(urls) == 6

      assert List.first(urls) ==
               "https://www.berlin.de/landesverwaltungsamt/_assets/logistikservice/amtsblatt-fuer-berlin/abl_2026_39_2749_2776_online.pdf"
    end

    test "finds the pdf in the old page layout" do
      urls =
        "test/support/data/amtsblatt/index_page.html"
        |> File.read!()
        |> BerlinerAmtsblatt.find_download_urls()

      assert length(urls) == 7

      assert List.first(urls) ==
               "https://www.berlin.de/landesverwaltungsamt/_assets/logistikservice/amtsblatt-fuer-berlin/abl_2021_28_2389_2480_online.pdf"
    end
  end

  describe "import_folder/0" do
    test "checks the import folder and parses all files in it" do
      File.cp(
        "test/support/data/amtsblatt/abl_2021_28_2389_2480_online.pdf",
        Path.join(@import_path, "abl_2021_28_2389_2480_online.pdf")
      )

      {:ok, news_items} = Hierbautberlin.Importer.BerlinerAmtsblatt.import_folder()

      assert length(news_items) == 28

      titles = Enum.map(news_items, & &1.title)

      refute Enum.member?(titles, "Beitragsordnung")
      refute Enum.member?(titles, "Gebührenordnung")

      refute File.exists?(Path.join(@import_path, "abl_2021_28_2389_2480_online.pdf"))
      assert FileStorage.exists?("amtsblatt/abl_2021_28_2389_2480_online.pdf")

      clean_storage()
    end
  end

  describe "warn_if_outdated/1" do
    test "warns when there was no new issue for three weeks" do
      source = insert(:source, short_name: "BERLIN_AMTSBLATT")
      insert(:news_item, source: source, published_at: ~U[2026-09-11 13:26:08Z])

      assert BerlinerAmtsblatt.warn_if_outdated(~U[2026-09-20 00:00:00Z]) == :ok
      assert BerlinerAmtsblatt.warn_if_outdated(~U[2026-10-10 00:00:00Z]) == :outdated
    end
  end

  describe "import_webpage/2" do
    test "does not store the pdf when the import fails, so it is retried" do
      assert {:error, _error} = BerlinerAmtsblatt.import_webpage(ImportMock, BrokenDownloadMock)
      refute FileStorage.exists?("amtsblatt/abl_2021_28_2389_2480_online.pdf")

      assert {:ok, news_items} = BerlinerAmtsblatt.import_webpage(ImportMock, DownloadMock)
      assert length(news_items) == 28
      assert FileStorage.exists?("amtsblatt/abl_2021_28_2389_2480_online.pdf")

      clean_storage()
    end

    test "downloads a pdf file and parses it" do
      {:ok, news_items} =
        Hierbautberlin.Importer.BerlinerAmtsblatt.import_webpage(ImportMock, DownloadMock)

      assert length(news_items) == 28

      first = List.first(news_items)

      assert first.title ==
               "Förderbekanntmachung landesweiter Maßnahmen im Land Berlin zum DigitalPakt Schule 2019 bis 2024"

      assert first.url ==
               "/view_pdf/amtsblatt/abl_2021_28_2389_2480_online.pdf?page=4&title=F%C3%B6rderbekanntmachung+landesweiter+Ma%C3%9Fnahmen+im+Land+Berlin+zum+DigitalPakt+Schule+2019+bis+2024"

      last = List.last(news_items)

      assert last.title ==
               "Widmung einer öffentlichen Grün- und Erholungsanlage"

      assert last.url ==
               "/view_pdf/amtsblatt/abl_2021_28_2389_2480_online.pdf?page=61&title=Widmung+einer+%C3%B6ffentlichen+Gr%C3%BCn-+und+Erholungsanlage"

      assert FileStorage.exists?("amtsblatt/abl_2021_28_2389_2480_online.pdf")

      file = FileStorage.get_file_by_name!("amtsblatt/abl_2021_28_2389_2480_online.pdf")
      assert file.title == "Amtsblatt für Berlin, 71. Jahrgang Nr. 28"

      filename = FileStorage.path_for_file(file)

      assert BerlinerAmtsblatt.get_number_of_pages(filename) == 61

      clean_storage()
    end
  end

  describe "import_amtsblatt/1" do
    test "imports a complete pdf" do
      park = insert(:place, name: "Lernmanagementsysteme")
      AnalyzeText.add_places([park])

      street = insert(:street, name: "DigitalPakt Schule")
      AnalyzeText.add_streets([street])

      result =
        BerlinerAmtsblatt.import_amtsblatt(
          "test/support/data/amtsblatt/abl_2021_28_2389_2480_online.pdf",
          8
        )

      assert Enum.map(result, & &1.title) == [
               "Förderbekanntmachung landesweiter Maßnahmen im Land Berlin zum DigitalPakt Schule 2019 bis 2024",
               "Festsetzung des Abstimmungstages für den Volksentscheid Vergesellschaftung",
               "Rundschreiben Soz Nummer 05/2021 Veröffentlichung des neuen Teilhabebedarfsermittlungsinstruments nach § 4 TIBV des Trägers der Eingliederungshilfe Berlin"
             ]

      first_news = Enum.at(result, 0)

      assert String.starts_with?(
               first_news.content,
               "Bekanntmachung vom 26. Mai 2021"
             )

      assert List.first(first_news.geo_places).name == "Lernmanagementsysteme"
      assert List.first(first_news.geo_streets).name == "DigitalPakt Schule"

      assert first_news.geometries == %Geo.GeometryCollection{
               geometries: [
                 %Geo.LineString{
                   coordinates: [{13.0, 52.0}, {13.01, 51.01}],
                   properties: %{},
                   srid: 4326
                 },
                 %Geo.Polygon{
                   coordinates: [[{13.0, 52.0}, {13.1, 52.1}, {13.1, 52.0}, {13.0, 52.0}]],
                   properties: %{},
                   srid: 4326
                 }
               ],
               properties: %{},
               srid: 4326
             }

      assert first_news.external_id ==
               "/view_pdf/amtsblatt/abl_2021_28_2389_2480_online.pdf?page=4&title=F%C3%B6rderbekanntmachung+landesweiter+Ma%C3%9Fnahmen+im+Land+Berlin+zum+DigitalPakt+Schule+2019+bis+2024"

      assert first_news.url ==
               "/view_pdf/amtsblatt/abl_2021_28_2389_2480_online.pdf?page=4&title=F%C3%B6rderbekanntmachung+landesweiter+Ma%C3%9Fnahmen+im+Land+Berlin+zum+DigitalPakt+Schule+2019+bis+2024"

      assert String.starts_with?(
               Enum.at(result, 1).content,
               "Bekanntmachung vom 6. Juli 2021"
             )

      AnalyzeText.reset_index()
    end
  end

  describe "get_date_from_file/1" do
    test "returns the date from a filename" do
      assert ~D[2021-07-09] ==
               BerlinerAmtsblatt.get_date_from_filename(
                 "test/support/data/amtsblatt/abl_2021_28_2389_2480_online.pdf"
               )
    end
  end

  describe "get_number_of_pages/1" do
    test "returns the number of pages" do
      assert 92 ==
               BerlinerAmtsblatt.get_number_of_pages(
                 "test/support/data/amtsblatt/abl_2021_28_2389_2480_online.pdf"
               )
    end
  end

  describe "get_structure/1" do
    test "returns the structure as map" do
      structure =
        BerlinerAmtsblatt.get_structure(
          "test/support/data/amtsblatt/abl_2021_28_2389_2480_online.pdf"
        )

      assert length(structure) == 79

      assert List.first(structure) == %{
               level: 1,
               page_number: nil,
               title: "Inhalt"
             }

      assert Enum.at(structure, 10) == %{
               level: 2,
               page_number: 20,
               title: "Baukammer Berlin"
             }

      assert List.last(structure) == %{
               level: 1,
               page_number: nil,
               title: "Nicht amtlicher Teil"
             }
    end
  end

  describe "get_last_page/2" do
    test "gets the last page we want to process" do
      structure =
        BerlinerAmtsblatt.get_structure(
          "test/support/data/amtsblatt/abl_2021_28_2389_2480_online.pdf"
        )

      assert BerlinerAmtsblatt.get_last_page(structure, 92) == 61
    end
  end

  describe "extract_page/2" do
    test "extracts a page and removes footer/header lines" do
      text =
        BerlinerAmtsblatt.extract_page(
          "test/support/data/amtsblatt/abl_2021_28_2389_2480_online.pdf",
          38
        )

      assert String.starts_with?(text, "Pankow")
      assert String.ends_with?(text, "informieren.")
    end

    test "extracts a page and removes footer/header lines even if header is duplicated" do
      text =
        BerlinerAmtsblatt.extract_page(
          "test/support/data/amtsblatt/abl_2021_28_2389_2480_online.pdf",
          33
        )

      assert String.starts_with?(text, "Mitte")
      assert String.ends_with?(text, "fenen.")
    end
  end

  describe "extract_news/2" do
    test "extracts news that are on the same page" do
      page =
        BerlinerAmtsblatt.extract_page(
          "test/support/data/amtsblatt/abl_2021_28_2389_2480_online.pdf",
          38
        )

      structure = [
        %{
          level: 2,
          page_number: 1,
          title: "Pankow"
        },
        %{
          level: 2,
          page_number: 1,
          title: "Pankow"
        }
      ]

      result = BerlinerAmtsblatt.extract_news([page], structure)
      assert length(result) == 2
      [first, second] = result

      assert first.title == "Ungültigkeitserklärung eines Dienstsiegels"

      assert first.item == %{
               level: 2,
               page_number: 1,
               title: "Pankow"
             }

      assert first.description ==
               "Bekanntmachung vom 25. Juni 2021\nFM ID 131\nTelefon: 90295-7235 oder 90295-0, intern 9295-7235\n\nBeim Bezirksamt Pankow von Berlin ist nachstehend näher beschriebenes Siegel mit\ndem Landeswappen von Berlin verlorengegangen"

      assert String.starts_with?(first.full_text, "Ungültigkeitserklärung eines")
      assert String.ends_with?(first.full_text, "Telefonnummer zu\ninformieren.")

      assert second.title == "Ungültigkeitserklärung eines Dienstsiegels"

      assert second.item == %{
               level: 2,
               page_number: 1,
               title: "Pankow"
             }

      assert second.description ==
               "Bekanntmachung vom 25. Juni 2021\nFM ID 131\nTelefon: 90295-7235 oder 90295-0, intern 9295-7235\n\nBeim Bezirksamt Pankow von Berlin ist nachstehend näher beschriebenes Siegel mit\ndem Landeswappen von Berlin verlorengegangen"

      assert String.starts_with?(second.full_text, "Ungültigkeitserklärung eines")
      assert String.ends_with?(second.full_text, "Telefonnummer zu\ninformieren.")
    end

    test "extracts news where the title is split in two rows" do
      page = """
      Senatsverwaltung für Justiz, Verbraucherschutz
      und Antidiskriminierung

      Hier ist der Titel

      Und hier der Text.
      """

      structure = [
        %{
          level: 2,
          page_number: 1,
          title: "Senatsverwaltung für Justiz, Verbraucherschutz und Antidiskriminierung"
        }
      ]

      result = BerlinerAmtsblatt.extract_news([page], structure)

      assert result == [
               %{
                 description: "Und hier der Text.",
                 full_text: "Hier ist der Titel\n\nUnd hier der Text.",
                 item: %{
                   level: 2,
                   page_number: 1,
                   title: "Senatsverwaltung für Justiz, Verbraucherschutz und Antidiskriminierung"
                 },
                 title: "Hier ist der Titel"
               }
             ]
    end

    test "extract news that spans several pages and is not the last text" do
      pages = [
        """
        Test

        Pankow

        Hier ist der Titel

        Und hier der Text.
        """,
        """
        More pages
        """,
        """
        Noch mehr Text

        Friedrichshain-Kreuzberg

        News Item Titel
        """
      ]

      structure = [
        %{
          level: 2,
          page_number: 1,
          title: "Pankow"
        },
        %{
          level: 2,
          page_number: 3,
          title: "Friedrichshain-Kreuzberg"
        }
      ]

      result = BerlinerAmtsblatt.extract_news(pages, structure)

      assert result == [
               %{
                 description: "Und hier der Text",
                 full_text:
                   "Hier ist der Titel\n\nUnd hier der Text.\n\nMore pages\n\nNoch mehr Text",
                 item: %{level: 2, page_number: 1, title: "Pankow"},
                 title: "Hier ist der Titel"
               },
               %{
                 description: "",
                 full_text: "News Item Titel",
                 item: %{level: 2, page_number: 3, title: "Friedrichshain-Kreuzberg"},
                 title: "News Item Titel"
               }
             ]
    end

    test "extract news that spans two pages" do
      pages = [
        """
        Test

        Pankow

        Hier ist der Titel

        Und hier der Text.
        """,
        """
        Noch mehr Text

        Friedrichshain-Kreuzberg

        News Item Titel
        """
      ]

      structure = [
        %{
          level: 2,
          page_number: 1,
          title: "Pankow"
        },
        %{
          level: 2,
          page_number: 2,
          title: "Friedrichshain-Kreuzberg"
        }
      ]

      result = BerlinerAmtsblatt.extract_news(pages, structure)

      assert result == [
               %{
                 description: "Und hier der Text",
                 full_text: "Hier ist der Titel\n\nUnd hier der Text.\n\nNoch mehr Text",
                 item: %{level: 2, page_number: 1, title: "Pankow"},
                 title: "Hier ist der Titel"
               },
               %{
                 description: "",
                 full_text: "News Item Titel",
                 item: %{level: 2, page_number: 2, title: "Friedrichshain-Kreuzberg"},
                 title: "News Item Titel"
               }
             ]
    end

    test "extract news that spans several pages and the next one starts right at the top of the page" do
      pages = [
        """
        Test

        Pankow

        Hier ist der Titel

        Und hier der Text.
        """,
        """
        More pages
        """,
        """
        Friedrichshain-Kreuzberg

        News Item Titel
        """
      ]

      structure = [
        %{
          level: 2,
          page_number: 1,
          title: "Pankow"
        },
        %{
          level: 2,
          page_number: 3,
          title: "Friedrichshain-Kreuzberg"
        }
      ]

      result = BerlinerAmtsblatt.extract_news(pages, structure)

      assert result == [
               %{
                 description: "Und hier der Text",
                 full_text: "Hier ist der Titel\n\nUnd hier der Text.\n\nMore pages",
                 item: %{level: 2, page_number: 1, title: "Pankow"},
                 title: "Hier ist der Titel"
               },
               %{
                 description: "",
                 full_text: "News Item Titel",
                 item: %{level: 2, page_number: 3, title: "Friedrichshain-Kreuzberg"},
                 title: "News Item Titel"
               }
             ]
    end

    test "extract news that spans several pages and is the last text" do
      pages = [
        """
        Test

        Pankow

        Hier ist der Titel

        Und hier der Text.
        """,
        """
        More pages
        """
      ]

      structure = [
        %{
          level: 2,
          page_number: 1,
          title: "Pankow"
        }
      ]

      result = BerlinerAmtsblatt.extract_news(pages, structure)

      assert result == [
               %{
                 description: "Und hier der Text",
                 full_text: "Hier ist der Titel\n\nUnd hier der Text.\n\nMore pages",
                 item: %{level: 2, page_number: 1, title: "Pankow"},
                 title: "Hier ist der Titel"
               }
             ]
    end

    test "extract news with multi line titles" do
      pages = [
        """
        Test

        Pankow

        Hier ist der Titel
        des Eintrages

        Und hier der Text.
        """,
        """
        More pages
        """
      ]

      structure = [
        %{
          level: 2,
          page_number: 1,
          title: "Pankow"
        }
      ]

      result = BerlinerAmtsblatt.extract_news(pages, structure)

      assert result == [
               %{
                 description: "Und hier der Text",
                 full_text:
                   "Hier ist der Titel\ndes Eintrages\n\nUnd hier der Text.\n\nMore pages",
                 item: %{level: 2, page_number: 1, title: "Pankow"},
                 title: "Hier ist der Titel des Eintrages"
               }
             ]
    end
  end

  describe "find_section/3" do
    test "it finds a simple title" do
      page = ["Line 1", "This is a title", "Content"]
      assert {1, 1} = BerlinerAmtsblatt.find_section(page, "This is a title", 0)
    end

    test "it finds a title with a different starting position" do
      page = ["Line 1", "This is a title", "Content", "This is a title", "Another Content"]
      assert {3, 3} = BerlinerAmtsblatt.find_section(page, "This is a title", 2)
    end

    test "it finds a multi line title with a different starting position" do
      page = ["Line 1", "This is a title", "Content", "This is", "a", "title", "Another Content"]
      assert {3, 5} = BerlinerAmtsblatt.find_section(page, "This is a title", 2)
    end

    test "it finds a multi line title with a different starting position and tons of whitespace" do
      page = [
        "Line 1",
        "This is a title",
        "Content",
        "  This is   ",
        " a ",
        "",
        "title",
        "Another Content"
      ]

      assert {3, 6} = BerlinerAmtsblatt.find_section(page, "This is a title", 2)
    end

    test "it ignores different spacing" do
      page = ["Line 1", "Vollzug des Gesetzes (IfSG) -", "Isolation von Personen", "Content"]

      assert {1, 2} =
               BerlinerAmtsblatt.find_section(
                 page,
                 "Vollzug des Gesetzes (IfSG) -Isolation von Personen"
               )
    end

    test "it finds a truncated title" do
      page = ["Line 1", "This is a very", "long title", "Content"]
      assert {1, 2} = BerlinerAmtsblatt.find_section(page, "This is a very lo...")
    end
  end

  describe "cut_at_skipped_section/1" do
    test "cuts the text at the heading of a skipped section" do
      text =
        "Einziehung von Straßenland\n\nDie Straße wird eingezogen.\n\nZweiradmechaniker Innung Berlin\n\nNeue Gebühren\nDie Zweiradmechaniker Innung Berlin, Manfred-von-Richthofen-Straße 30"

      assert BerlinerAmtsblatt.cut_at_skipped_section(text) ==
               "Einziehung von Straßenland\n\nDie Straße wird eingezogen."
    end

    test "keeps mentions in the text" do
      text = "Titel\n\nDie Baukammer Berlin hat beschlossen:\nText"
      assert BerlinerAmtsblatt.cut_at_skipped_section(text) == text
    end
  end

  describe "trim_and_join_lines/1" do
    test "it joins several lines" do
      assert "Line 1\nLine 2\nLine 3" ==
               BerlinerAmtsblatt.trim_and_join_lines(["   Line 1", "Line 2     ", " Line 3 "])
    end

    test "it dehyphens the text" do
      assert "Diese Zeilenlänge benötigt leider umbrueche.\nWie auch in der Herman-Mueller-Strasse.\nUnd 5-7 ist...\nAber a-z ist..." ==
               BerlinerAmtsblatt.trim_and_join_lines([
                 "Diese Zeilen-",
                 "länge benötigt leider umbrueche.",
                 "Wie auch in der Herman-",
                 "Mueller-Strasse.",
                 "Und 5-",
                 "7 ist...",
                 "Aber a-",
                 "z ist..."
               ])
    end
  end
end
