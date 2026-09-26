defmodule Hierbautberlin.GeoData.AddressMatcherTest do
  use Hierbautberlin.DataCase, async: false

  alias Hierbautberlin.GeoData.AddressMatcher

  defp street(attrs) do
    Map.merge(%{ortsteil: nil, number_count: 20, district: "Mitte"}, Map.new(attrs))
  end

  defp analyze(text, streets, places \\ [], options \\ %{}) do
    AddressMatcher.analyze(text, options, AddressMatcher.build_index(streets, places))
  end

  test "ignores generic single word street names" do
    streets = [street(id: 1, name: "Weg", number_count: 0), street(id: 2, name: "Innenhof")]

    assert %{streets: []} = analyze("Auf kürzerem Weg in den neuen Innenhof", streets)
  end

  test "accepts single word names with a location cue or many addresses" do
    streets = [
      street(id: 1, name: "Popitzweg", number_count: 3),
      street(id: 2, name: "Halemweg", number_count: 50)
    ]

    assert %{streets: [1]} = analyze("Die Baustelle am Popitzweg", streets)
    assert %{streets: []} = analyze("Der Popitzweg wird gebaut", streets)
    assert %{streets: [2]} = analyze("Die Bibliothek Halemweg", streets)
  end

  test "a street named like an Ortsteil needs a house number" do
    streets = [
      street(id: 1, name: "Prenzlauer Berg", ortsteil: "Prenzlauer Berg", district: "Pankow"),
      street(id: 2, name: "Behmstraße", ortsteil: "Prenzlauer Berg", district: "Pankow")
    ]

    # the Ortsteil is meant, and it is still the district context of the other street
    assert %{streets: [2]} =
             analyze("Markierungsarbeiten in der Behmstraße in Prenzlauer Berg", streets)

    assert %{streets: [], street_numbers: []} = analyze("Ein Fest im Prenzlauer Berg", streets)

    # with a house number the street is meant. The number is not in this index,
    # so it stays a context street instead of a point (see `interpolate_numbers/1`)
    assert %{streets: [], context_streets: [1]} =
             analyze("Die Baustelle Prenzlauer Berg 12", streets)
  end

  test "ignores streets that are only numbers" do
    assert %{streets: []} = analyze("Telefon 7 oder 8", [street(id: 1, name: "7")])
  end

  test "handles declined names and genitives" do
    streets = [
      street(id: 1, name: "Alter Schönefelder Weg", district: "Treptow-Köpenick"),
      street(id: 2, name: "Stuttgarter Platz", district: "Charlottenburg-Wilmersdorf")
    ]

    result =
      analyze("Am Alten Schönefelder Weg und auf der Fläche des Stuttgarter Platzes", streets)

    assert Enum.sort(result.streets) == [1, 2]
  end

  test "joins words hyphenated with a soft hyphen at the end of a line" do
    streets = [street(id: 1, name: "Thiemannstraße", district: "Neukölln")]
    assert %{streets: [1]} = analyze("zwischen Treptower Straße und Thiemann­\nstraße", streets)
  end

  test "uses the district context to pick the right street" do
    streets = [
      street(id: 1, name: "Hauptstraße", district: "Lichtenberg"),
      street(id: 2, name: "Hauptstraße", district: "Tempelhof-Schöneberg")
    ]

    assert %{streets: []} = analyze("An der Hauptstraße wird gebaut", streets)

    assert %{streets: [2]} =
             analyze("An der Hauptstraße wird gebaut", streets, [], %{
               districts: ["Tempelhof-Schöneberg"]
             })

    assert %{streets: [1]} = analyze("An der Hauptstraße in Lichtenberg wird gebaut", streets)
  end

  test "takes all parts of a street that crosses a district border on a tie" do
    streets = [
      street(id: 1, name: "Hansastraße", district: "Mitte"),
      street(id: 2, name: "Hansastraße", district: "Lichtenberg", connected: [3]),
      street(id: 3, name: "Hansastraße", district: "Pankow", connected: [2])
    ]

    text = "Radweg in der Hansastraße in den Ortsteilen Weißensee und Alt-Hohenschönhausen"

    assert %{streets: []} = analyze("Radweg in der Hansastraße", streets)
    assert %{streets: []} = analyze("Radweg in der Hansastraße in Mitte oder Pankow", streets)

    result =
      analyze(
        text,
        streets ++
          [
            street(id: 4, name: "Egal", ortsteil: "Weißensee", district: "Pankow"),
            street(id: 5, name: "Egal", ortsteil: "Alt-Hohenschönhausen", district: "Lichtenberg")
          ]
      )

    assert Enum.sort(result.streets) == [2, 3]
  end

  test "district names must be whole words" do
    streets = [
      street(id: 1, name: "Hauptstraße", district: "Mitte"),
      street(id: 2, name: "Hauptstraße", district: "Pankow")
    ]

    assert %{streets: []} =
             analyze("Aus Mitteln des Bezirks wird die Hauptstraße saniert", streets)
  end

  test "finds lists of house numbers" do
    street =
      insert(:street,
        name: "Schulzendorfer Straße",
        district: "Reinickendorf",
        street_numbers: []
      )

    one = insert(:street_number, geo_street_id: street.id, number: "1")
    three = insert(:street_number, geo_street_id: street.id, number: "3")

    streets = [%{id: street.id, name: street.name, district: street.district, number_count: 2}]

    result = analyze("die Flurstücke Schulzendorfer Straße 1 und 3 in Berlin", streets)
    assert Enum.sort(result.street_numbers) == Enum.sort([one.id, three.id])
    assert result.streets == []
  end

  test "ignores addresses of authorities in legal notices" do
    street = insert(:street, name: "Karl-Marx-Straße", district: "Neukölln", street_numbers: [])
    insert(:street_number, geo_street_id: street.id, number: "83")
    streets = [%{id: street.id, name: street.name, district: street.district, number_count: 1}]

    text = """
    Die Nummerierungspläne können im Bezirksamt Neukölln von Berlin, Zimmer N 6012,
    Karl-Marx-Straße 83, 12040 Berlin, eingesehen werden.
    """

    assert %{streets: [], street_numbers: []} = analyze(text, streets)
  end

  test "ignores LOR planning areas named like a street or an Ortsteil" do
    streets = [street(id: 1, name: "Siemensdamm", district: "Spandau", ortsteil: "Siemensstadt")]

    places = [
      %{id: 10, name: "Siemensdamm", district: "Spandau", type: "LOR"},
      %{id: 11, name: "Siemensstadt", district: "Spandau", type: "LOR"},
      %{id: 12, name: "Helle Mitte", district: "Marzahn-Hellersdorf", type: "LOR"}
    ]

    result = analyze("Siemensdamm in Siemensstadt und die Helle Mitte", streets, places)
    assert result.streets == [1]
    assert result.places == [12]
  end

  test "generic place names need a matching district if the district is known" do
    places = [
      %{id: 1, name: "Rosengarten", district: "Mitte", type: "Park"},
      %{id: 2, name: "Rosengarten", district: "Spandau", type: "Park"}
    ]

    assert %{places: []} =
             analyze("Der Rosengarten wird eröffnet", [], places, %{districts: ["Reinickendorf"]})

    assert %{places: [2]} =
             analyze("Der Rosengarten wird eröffnet", [], places, %{districts: ["Spandau"]})
  end
end
