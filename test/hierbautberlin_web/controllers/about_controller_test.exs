defmodule HierbautberlinWeb.AboutControllerTest do
  use HierbautberlinWeb.ConnCase, async: true

  test "tells what the site is, who built it and where the data comes from", %{conn: conn} do
    insert(:source, name: "Amtsblatt für Berlin", url: "https://example.com/amtsblatt")

    html = conn |> get(~p"/ueber-uns") |> html_response(200)

    assert html =~ "Über Hier Baut Berlin"
    assert html =~ ~s(<a href="https://bodo.tasche.me">Bodo Tasche</a>)
    assert html =~ ~s(<a href="https://example.com/amtsblatt">Amtsblatt für Berlin</a>)
    assert html =~ ~r/<meta name="description" content="Hier Baut Berlin sammelt/
    assert html =~ "Über uns"
  end

  test "is linked in the menu and the footer", %{conn: conn} do
    html = conn |> get(~p"/impressum") |> html_response(200)

    assert html =~ ~s(<a href="/ueber-uns">Über uns</a>)
    assert [_, _] = Regex.scan(~r{href="/ueber-uns"}, html) |> Enum.take(2)
  end
end
