defmodule HierbautberlinWeb.MapLiveTest do
  use HierbautberlinWeb.ConnCase

  import Phoenix.LiveViewTest
  import Hierbautberlin.AccountsFixtures

  alias Hierbautberlin.Accounts
  alias Hierbautberlin.GeoData.MapFeatures

  defp point(lng, lat), do: %Geo.Point{coordinates: {lng, lat}, srid: 4326}

  defp all_source_ids do
    Hierbautberlin.GeoData.list_sources() |> Enum.map(&to_string(&1.id))
  end

  setup do
    near = insert(:geo_item, title: "Near Item", geo_point: point(13.2679, 52.51))
    far = insert(:geo_item, title: "Far Item", geo_point: point(13.5, 52.4))
    MapFeatures.refresh()

    %{near: near, far: far}
  end

  test "renders the items near the position from the url", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/map?lat=52.51&lng=13.2679&zoom=15")

    assert html =~ "Near Item"
    refute html =~ "Far Item"
    assert has_element?(view, "#map-page[data-tiles-url^='/tiles/items/']")
  end

  describe "remembered position" do
    test "opens the map at the position the browser remembered", %{conn: conn} do
      conn =
        put_connect_params(conn, %{
          "map_position" => %{"lat" => 52.4, "lng" => 13.5, "zoom" => 16}
        })

      {:ok, view, _html} = live(conn, ~p"/map")

      html = render(view)
      assert html =~ "Far Item"
      refute html =~ "Near Item"
      assert has_element?(view, "#map-page[data-position-lat='52.4'][data-position-zoom='16.0']")
    end

    test "the position in the url wins", %{conn: conn} do
      conn =
        put_connect_params(conn, %{
          "map_position" => %{"lat" => 52.4, "lng" => 13.5, "zoom" => 16}
        })

      {:ok, view, _html} = live(conn, ~p"/map?lat=52.51&lng=13.2679&zoom=15")

      assert render(view) =~ "Near Item"
      assert has_element?(view, "#map-page[data-position-lat='52.51']")
    end

    test "positions outside of Berlin open the center of Berlin", %{conn: conn} do
      conn =
        put_connect_params(conn, %{"map_position" => %{"lat" => 0.0, "lng" => 0.0, "zoom" => 15}})

      {:ok, view, _html} = live(conn, ~p"/map")

      assert has_element?(
               view,
               "#map-page[data-position-lat='52.5166309'][data-position-lng='13.3781537']"
             )

      {:ok, view, _html} = live(conn, ~p"/map?lat=0.0&lng=0.0&zoom=15.0")

      assert has_element?(
               view,
               "#map-page[data-position-lat='52.5166309'][data-position-lng='13.3781537']"
             )
    end

    test "ignores invalid positions", %{conn: conn} do
      conn = put_connect_params(conn, %{"map_position" => %{"lat" => "evil", "lng" => 500}})
      {:ok, view, _html} = live(conn, ~p"/map")

      assert has_element?(view, "#map-page[data-position-lat='52.5166309']")
    end
  end

  test "renders the welcome box hidden, the browser shows it the first time", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/map")

    assert has_element?(view, "#welcome-box[hidden][phx-hook='WelcomeBox']")
    assert has_element?(view, "#welcome-box .map--welcome--close[data-welcome-close]")

    assert has_element?(
             view,
             "#welcome-box .map--welcome--start[data-welcome-close]",
             "Karte ansehen"
           )
  end

  describe "list toolbar" do
    test "hides sources in the list and on the map", %{conn: conn, near: near} do
      {:ok, view, _html} = live(conn, ~p"/map?lat=52.51&lng=13.2679&zoom=15")
      assert render(view) =~ "Near Item"
      refute has_element?(view, "#list-filter-button.map--list-tool--button-active")

      other_sources =
        Hierbautberlin.GeoData.list_sources() |> Enum.reject(&(&1.id == near.source_id))

      html =
        view
        |> form("#list-filter-form")
        |> render_change(%{
          "sources" => Enum.map(other_sources, &to_string(&1.id)),
          "show_old" => "on"
        })

      refute html =~ "Near Item"
      assert html =~ "Keine Einträge passen zu den Filtern."
      assert has_element?(view, "#list-filter-button.map--list-tool--button-active")
      assert has_element?(view, "#map-page[data-hidden-sources='[#{near.source_id}]']")

      assert has_element?(
               view,
               "input[name='sources[]'][value='#{near.source_id}']:not([checked])"
             )

      html =
        view |> element("#list-filter-popup button", "Alle Quellen anzeigen") |> render_click()

      assert html =~ "Near Item"
      refute has_element?(view, "#list-filter-button.map--list-tool--button-active")
    end

    test "hides old and finished entries", %{conn: conn} do
      insert(:geo_item,
        title: "Finished Item",
        state: "finished",
        geo_point: point(13.2679, 52.51)
      )

      insert(:geo_item,
        title: "Old Item",
        date_end: DateTime.utc_now() |> DateTime.add(-400, :day) |> DateTime.truncate(:second),
        geo_point: point(13.2679, 52.51)
      )

      MapFeatures.refresh()

      {:ok, view, _html} = live(conn, ~p"/map?lat=52.51&lng=13.2679&zoom=15")
      assert has_element?(view, "#map-page[data-show-old='true']")
      assert has_element?(view, "input[name='show_old'][checked]")

      # an unchecked checkbox is not sent at all, so the form data has no show_old
      html = render_change(view, "filter-list", %{"sources" => all_source_ids()})

      refute html =~ "Finished Item"
      refute html =~ "Old Item"
      assert html =~ "Near Item"
      assert has_element?(view, "#map-page[data-show-old='false']")
      assert has_element?(view, "#list-filter-button.map--list-tool--button-active")
      assert has_element?(view, "input[name='show_old']:not([checked])")

      html =
        render_change(view, "filter-list", %{"sources" => all_source_ids(), "show_old" => "on"})

      assert html =~ "Finished Item"
      assert html =~ "Old Item"
      refute has_element?(view, "#list-filter-button.map--list-tool--button-active")
    end

    test "offers to show the old entries again when nothing is left", %{conn: conn, near: near} do
      near |> Ecto.Changeset.change(state: "finished") |> Hierbautberlin.Repo.update!()
      MapFeatures.refresh()

      {:ok, view, _html} = live(conn, ~p"/map?lat=52.51&lng=13.2679&zoom=15")
      html = render_change(view, "filter-list", %{"sources" => all_source_ids()})

      assert html =~ "Keine Einträge passen zu den Filtern."

      html =
        view
        |> element(".map--item-list--empty button", "Alte und erledigte Einträge anzeigen")
        |> render_click()

      assert html =~ "Near Item"
    end

    test "restores the filters the browser remembered", %{conn: conn, near: near} do
      conn =
        put_connect_params(conn, %{
          "list_filters" => %{
            "hidden_sources" => [near.source_id, -1, "evil"],
            "show_old" => false
          }
        })

      {:ok, view, _html} = live(conn, ~p"/map?lat=52.51&lng=13.2679&zoom=15")

      refute render(view) =~ "Near Item"
      assert has_element?(view, "#map-page[data-hidden-sources='[#{near.source_id}]']")
      assert has_element?(view, "#map-page[data-show-old='false']")
      assert has_element?(view, "input[name='show_old']:not([checked])")
    end

    test "searches in the list and shows the search", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/map?lat=52.51&lng=13.2679&zoom=15")

      html =
        view
        |> form("#list-search-form", list_search: %{query: "Nothing like this"})
        |> render_change()

      refute html =~ "Near Item"

      assert has_element?(
               view,
               "#list-search-button .map--list-tool--query",
               "„Nothing like this“"
             )

      assert has_element?(view, "button[aria-label='Suche „Nothing like this“ entfernen']")

      html = view |> element(".map--list-tool--clear") |> render_click()
      assert html =~ "Near Item"
      refute has_element?(view, ".map--list-tool--clear")

      # shorter searches are not applied
      html = view |> form("#list-search-form", list_search: %{query: "xy"}) |> render_change()
      assert html =~ "Near Item"
      refute has_element?(view, ".map--list-tool--clear")
    end

    test "the popups are accessible", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/map")

      assert has_element?(
               view,
               "#list-filter-button[aria-expanded='false'][aria-controls='list-filter-popup']"
             )

      assert has_element?(view, "#list-filter-popup fieldset legend", "Quellen anzeigen")

      assert has_element?(
               view,
               "#list-filter-popup .map--list-popup--option",
               "Alte und erledigte Einträge"
             )

      assert has_element?(view, "#list-search-popup label[for='list-search-query']")
    end

    test "the list can be collapsed on phones", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/map")

      assert has_element?(
               view,
               "#list-collapse-button[aria-expanded='true'][aria-controls='map-list-body']",
               "Liste"
             )

      assert has_element?(view, "#map-list-body #map-item-list")
      assert has_element?(view, "#map-list-body .map--item-list-footer")
      refute has_element?(view, "#map-list-wrapper.map--item-list-wrapper-collapsed")
    end

    test "collapsing the list keeps it in the url", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/map?lat=52.51&lng=13.2679&zoom=15")

      render_click(view, "toggle_list")
      assert_patch(view, ~p"/map?lat=52.51&lng=13.2679&zoom=15.0&list=collapsed")
      assert has_element?(view, "#map-list-wrapper.map--item-list-wrapper-collapsed")
      assert has_element?(view, "#list-collapse-button[aria-expanded='false']")

      render_click(view, "toggle_list")
      assert_patch(view, ~p"/map?lat=52.51&lng=13.2679&zoom=15.0")
      assert has_element?(view, "#list-collapse-button[aria-expanded='true']")
    end

    test "renders the list collapsed with the url parameter", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/map?list=collapsed")

      assert html =~ "map--item-list-wrapper-collapsed"
      assert has_element?(view, "#list-collapse-button[aria-expanded='false']")
    end
  end

  describe "meta tags" do
    test "a shared entry has its own description and canonical url", %{conn: conn, near: near} do
      long_text = String.duplicate("Die Straße wird erneuert und bekommt neue Radwege. ", 10)

      near
      |> Ecto.Changeset.change(description: long_text)
      |> Hierbautberlin.Repo.update!()

      html =
        conn
        |> get(~p"/map?lat=52.51&lng=13.2679&zoom=15&details=#{near.id}&detailsType=geo_item")
        |> html_response(200)

      link = "http://localhost:4002/map?details=#{near.id}&amp;detailsType=geo_item"

      assert html =~ ~s(<link rel="canonical" href="#{link}")
      assert html =~ ~s(<meta property="og:url" content="#{link}")
      assert html =~ ~s(<meta property="og:type" content="article")
      assert html =~ ~s(<meta property="og:title" content="Hier Baut Berlin - Near Item")
      assert html =~ ~s(<meta name="description" content="Die Straße wird erneuert und bekommt)
      # the description is cut off after 200 characters, at a word boundary
      refute html =~ ~s(content="#{long_text}")

      assert [description] =
               Regex.run(~r/<meta name="description" content="([^"]+)"/, html,
                 capture: :all_but_first
               )

      assert String.length(description) <= 201
      assert String.ends_with?(description, "…")
    end

    test "the map itself is canonical without the position", %{conn: conn} do
      html = conn |> get(~p"/map?lat=52.51&lng=13.2679&zoom=15") |> html_response(200)

      assert html =~ ~s(<link rel="canonical" href="http://localhost:4002/map")
      refute html =~ ~s(<link rel="canonical" href="http://localhost:4002/map?)
    end

    test "links the favicons and the web manifest", %{conn: conn} do
      html = conn |> get(~p"/map") |> html_response(200)

      assert html =~ ~s(<link rel="icon" href="/favicon.ico" sizes="48x48")
      assert html =~ ~s(<link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png")
      assert html =~ ~s(<link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png")
      assert html =~ ~s(<link rel="manifest" href="/site.webmanifest")
    end

    test "the start page redirects permanently to the map", %{conn: conn} do
      assert conn |> get(~p"/") |> redirected_to(301) == "/map"
    end

    test "the paths of entries in the statistics open the entry", %{conn: conn, near: near} do
      path = conn |> get("/map/eintrag/geo_item/#{near.id}") |> redirected_to(302)
      assert path == "/map?details=#{near.id}&detailsType=geo_item"

      {:ok, _view, html} = live(conn, path)
      assert html =~ "Near Item"
    end
  end

  test "ignores unknown detail types", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/map?details=1&detailsType=evil")
    refute html =~ "details-modal"

    render_hook(view, "showDetails", %{"item-id" => "1", "item-type" => "evil"})
    refute render(view) =~ "details-modal"
  end

  test "the start page is the map", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/"), 301) == ~p"/map"
    assert redirected_to(get(conn, "/?lat=52.4&lng=13.5"), 301) == "/map?lat=52.4&lng=13.5"
  end

  test "updates the list when the map viewport changes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/map?lat=52.51&lng=13.2679&zoom=15")

    html =
      render_hook(view, "viewport", %{
        "center" => %{"lat" => 52.4, "lng" => 13.5},
        "zoom" => 15.123,
        "bounds" => %{"west" => 13.49, "south" => 52.39, "east" => 13.51, "north" => 52.41}
      })

    assert html =~ "Far Item"
    refute html =~ "Near Item"
    assert_patch(view, ~p"/map?lat=52.4&lng=13.5&zoom=15.12")
  end

  test "shows a hint when zoomed out too far", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/map?lat=52.51&lng=13.2679&zoom=5")

    assert html =~ "Zoome näher heran"
    refute html =~ "Near Item"
  end

  test "opens the details of an item", %{conn: conn, near: near} do
    {:ok, view, _html} = live(conn, ~p"/map?lat=52.51&lng=13.2679&zoom=15")

    html =
      view
      |> element("#list-item-geo_item-#{near.id}")
      |> render_click()

    assert html =~ "details-modal"
    assert html =~ "This is a description"

    assert_patch(
      view,
      ~p"/map?lat=52.51&lng=13.2679&zoom=15.0&details=#{near.id}&detailsType=geo_item"
    )
  end

  test "the details dialog focuses its content, not the first link further down", %{
    conn: conn,
    near: near
  } do
    {:ok, view, _html} =
      live(conn, ~p"/map?lat=52.51&lng=13.2679&zoom=15&details=#{near.id}&detailsType=geo_item")

    assert has_element?(view, "#details-modal .phx-modal-inner[role='dialog'][aria-modal='true']")
    assert has_element?(view, "#details-modal-content[tabindex='-1']")
    assert has_element?(view, "#details-geo_item-#{near.id}[phx-hook='DetailsScrollTop']")
    assert render(view) =~ ~r/phx-mounted="[^"]*details-modal-content/
  end

  describe "details map" do
    test "shows the location of the entry in the color of its source", %{conn: conn} do
      item =
        insert(:geo_item,
          title: "Colored Item",
          source: build(:source, color: "#FFB462", background_color: "#FF911A"),
          geo_point: point(13.2679, 52.51)
        )

      {:ok, view, _html} =
        live(conn, ~p"/map?lat=52.51&lng=13.2679&zoom=15&details=#{item.id}&detailsType=geo_item")

      assert has_element?(
               view,
               "#details-modal .details--map#details-map-geo_item-#{item.id}[phx-hook='DetailsMap'][data-color='#FFB462'][data-background-color='#FF911A']"
             )

      assert view |> element(".details--map") |> render() =~
               ~s(data-shape="{&quot;type&quot;:&quot;FeatureCollection&quot;)

      assert view |> element(".details--map") |> render() =~
               ~s(&quot;coordinates&quot;:[13.2679,52.51])

      assert view |> element(".details--map") |> render() =~
               ~s(&quot;draw&quot;:&quot;point&quot;)

      # the text comes first, the map after it
      assert render(view) =~ ~r/details--text.*details--map.*details--share/s
    end

    test "shows all places of a news item", %{conn: conn} do
      news_item =
        insert(:news_item,
          geo_points: %Geo.MultiPoint{coordinates: [{13.3, 52.5}, {13.4, 52.52}], srid: 4326}
        )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/map?lat=52.51&lng=13.2679&zoom=15&details=#{news_item.id}&detailsType=news_item"
        )

      assert view |> element(".details--map") |> render() =~
               "[[13.3,52.5],[13.4,52.52]]"
    end

    test "shows the polygon of an entry", %{conn: conn} do
      item =
        insert(:geo_item,
          geometry: %Geo.Polygon{
            coordinates: [[{13.26, 52.50}, {13.27, 52.50}, {13.27, 52.51}, {13.26, 52.50}]],
            srid: 4326
          }
        )

      {:ok, view, _html} =
        live(conn, ~p"/map?lat=52.51&lng=13.2679&zoom=15&details=#{item.id}&detailsType=geo_item")

      html = view |> element(".details--map") |> render()
      assert html =~ "&quot;draw&quot;:&quot;polygon&quot;"
      refute html =~ "&quot;draw&quot;:&quot;point&quot;"
    end
  end

  describe "sharing an entry" do
    test "the details have a share button with the link without position", %{
      conn: conn,
      near: near
    } do
      {:ok, view, _html} =
        live(conn, ~p"/map?lat=52.51&lng=13.2679&zoom=15&details=#{near.id}&detailsType=geo_item")

      assert has_element?(
               view,
               "#share-geo_item-#{near.id}[phx-hook='ShareButton'][data-url='http://localhost:4002/map?details=#{near.id}&detailsType=geo_item'][data-title='Near Item']"
             )

      assert has_element?(view, "#share-geo_item-#{near.id} button", "Teilen")
      assert has_element?(view, "#share-geo_item-#{near.id} [role='status']")
    end

    test "a shared link opens the map at the entry", %{conn: conn, far: far} do
      # the browser remembers another position, the entry wins
      conn =
        put_connect_params(conn, %{
          "map_position" => %{"lat" => 52.51, "lng" => 13.2679, "zoom" => 12}
        })

      {:ok, view, _html} = live(conn, ~p"/map?details=#{far.id}&detailsType=geo_item")

      assert has_element?(
               view,
               "#map-page[data-position-lat='52.4'][data-position-lng='13.5'][data-position-zoom='16']"
             )

      assert has_element?(view, "#details-modal", "Far Item")
    end

    test "a position in the link still wins", %{conn: conn, far: far} do
      {:ok, view, _html} =
        live(conn, ~p"/map?lat=52.51&lng=13.2679&zoom=15&details=#{far.id}&detailsType=geo_item")

      assert has_element?(view, "#map-page[data-position-lat='52.51']")
    end
  end

  test "opens details from the url", %{conn: conn} do
    news_item = insert(:news_item, title: "My news")

    {:ok, _view, html} =
      live(conn, ~p"/map?lat=52.51&lng=13.2679&details=#{news_item.id}&detailsType=news_item")

    assert html =~ "details-modal"
    assert html =~ "My news"
  end

  test "searches streets", %{conn: conn} do
    insert(:street, name: "Karl-Marx-Allee", street_number_count: 10)
    {:ok, view, _html} = live(conn, ~p"/map")

    html =
      view
      |> form(".map--search-form", search_field: %{query: "Karl"})
      |> render_change()

    assert html =~ "Karl-Marx-Allee"
    assert has_element?(view, "#search_field_query[role='combobox'][aria-expanded='true']")
    assert has_element?(view, "#map-search-results [role='option'][data-name='Karl-Marx-Allee']")

    html =
      view
      |> form(".map--search-form", search_field: %{query: "Qqqxyz"})
      |> render_change()

    assert html =~ "Keine Straße gefunden"

    render_hook(view, "hide-results", %{})
    assert has_element?(view, "#search_field_query[aria-expanded='false']")
  end

  test "subscribes to a location", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, ~p"/map?lat=52.51&lng=13.2679&zoom=15")

    html =
      view
      |> element(".map--item-list-footer--subscribe form")
      |> render_change(%{"subscribe" => "on"})

    assert html =~ "Neue Benachrichtigung"
    assert Accounts.get_subscription(user, %{lat: 52.51, lng: 13.2679})

    # the map with the radius, assets/js/subscriptionMap.ts
    assert has_element?(
             view,
             "[phx-hook='SubscriptionMap'][data-subscription-map][data-lat='52.51'][data-lng='13.2679'][data-radius]"
           )
  end
end
