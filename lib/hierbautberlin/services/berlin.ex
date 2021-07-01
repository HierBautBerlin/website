defmodule Hierbautberlin.Services.Berlin do
  @berlin_local_centers %{
    "Adlershof" => "Treptow-Köpenick",
    "Altglienicke" => "Treptow-Köpenick",
    "Alt-Hohenschönhausen" => "Lichtenberg",
    "Alt-Treptow" => "Treptow-Köpenick",
    "Baumschulenweg" => "Treptow-Köpenick",
    "Biesdorf" => "Marzahn-Hellersdorf",
    "Blankenburg" => "Pankow",
    "Blankenfelde" => "Pankow",
    "Bohnsdorf" => "Treptow-Köpenick",
    "Borigwalde" => "Reinickendorf",
    "Britz" => "Neukölln",
    "Buch" => "Pankow",
    "Buckow" => "Neukölln",
    "Charlottenburg" => "Charlottenburg-Wilmersdorf",
    "Charlottenburg-Nord" => "Charlottenburg-Wilmersdorf",
    "Dahlem" => "Steglitz-Zehlendorf",
    "Falkenberg" => "Lichtenberg",
    "Falkenhagener Feld" => "Spandau",
    "Fennpfuhl" => "Lichtenberg",
    "Französisch Buchholz" => "Pankow",
    "Friedenau" => "Tempelhof-Schöneberg",
    "Friedrichsfelde" => "Lichtenberg",
    "Friedrichshagen" => "Treptow-Köpenick",
    "Friedrichshain" => "Friedrichshain-Kreuzberg",
    "Frohnau" => "Reinickendorf",
    "Gatow" => "Spandau",
    "Gesundbrunnen" => "Mitte",
    "Gropiusstadt" => "Neukölln",
    "Grunewald" => "Charlottenburg-Wilmersdorf",
    "Grünau" => "Treptow-Köpenick",
    "Hakenfelde" => "Spandau",
    "Halensee" => "Charlottenburg-Wilmersdorf",
    "Hansaviertel" => "Mitte",
    "Haselhorst" => "Spandau",
    "Heiligensee" => "Reinickendorf",
    "Heinersdorf" => "Pankow",
    "Hellersdorf" => "Marzahn-Hellersdorf",
    "Hermsdorf" => "Reinickendorf",
    "Johannisthal" => "Treptow-Köpenick",
    "Karow" => "Pankow",
    "Karlshorst" => "Lichtenberg",
    "Kaulsdorf" => "Marzahn-Hellersdorf",
    "Kladow" => "Spandau",
    "Kreuzberg" => "Friedrichshain-Kreuzberg",
    "Konradshöhe" => "Reinickendorf",
    "Köpenick" => "Treptow-Köpenick",
    "Lankwitz" => "Steglitz-Zehlendorf",
    "Lichtenberg" => "Lichtenberg",
    "Lichterfelde" => "Steglitz-Zehlendorf",
    "Lichtenrade" => "Tempelhof-Schöneberg",
    "Lübars" => "Reinickendorf",
    "Mahlsdorf" => "Marzahn-Hellersdorf",
    "Malchow" => "Lichtenberg",
    "Mariendorf" => "Tempelhof-Schöneberg",
    "Marienfelde" => "Tempelhof-Schöneberg",
    "Marzahn" => "Marzahn-Hellersdorf",
    "Märkisches Viertel" => "Reinickendorf",
    "Mitte" => "Mitte",
    "Moabit" => "Mitte",
    "Müggelheim" => "Treptow-Köpenick",
    "Neukölln" => "Neukölln",
    "Neu-Hohenschönhausen" => "Lichtenberg",
    "Niederschönhausen" => "Pankow",
    "Niederschöneweide" => "Treptow-Köpenick",
    "Nikolassee" => "Steglitz-Zehlendorf",
    "Oberschöneweide" => "Treptow-Köpenick",
    "Pankow" => "Pankow",
    "Plänterwald" => "Treptow-Köpenick",
    "Prenzlauer Berg" => "Pankow",
    "Rahnsdorf" => "Treptow-Köpenick",
    "Reinickendorf" => "Reinickendorf",
    "Rosenthal" => "Pankow",
    "Rudow" => "Neukölln",
    "Rummelsburg" => "Lichtenberg",
    "Schmargendorf" => "Charlottenburg-Wilmersdorf",
    "Schmöckwitz" => "Treptow-Köpenick",
    "Schöneberg" => "Tempelhof-Schöneberg",
    "Siemensstadt" => "Spandau",
    "Spandau" => "Spandau",
    "Staaken" => "Spandau",
    "Stadtrandsiedlung Malchow" => "Pankow",
    "Steglitz" => "Steglitz-Zehlendorf",
    "Tegel" => "Reinickendorf",
    "Tempelhof" => "Tempelhof-Schöneberg",
    "Tiergarten" => "Mitte",
    "Wannsee" => "Steglitz-Zehlendorf",
    "Wartenberg" => "Lichtenberg",
    "Waidmannslust" => "Reinickendorf",
    "Wedding" => "Mitte",
    "Westend" => "Charlottenburg-Wilmersdorf",
    "Weißensee" => "Pankow",
    "Wilhelmsruh" => "Pankow",
    "Wilmersdorf" => "Charlottenburg-Wilmersdorf",
    "Wilhelmstadt" => "Spandau",
    "Wittenau" => "Reinickendorf",
    "Zehlendorf" => "Steglitz-Zehlendorf"
  }

  def district_for_local_center(local_center) do
    @berlin_local_centers[local_center]
  end
end