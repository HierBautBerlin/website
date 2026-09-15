defmodule HierbautberlinWeb.SubscriptionControllerTest do
  use HierbautberlinWeb.ConnCase, async: true

  alias Hierbautberlin.Accounts
  import Hierbautberlin.AccountsFixtures

  setup do
    %{user: user_fixture()}
  end

  describe "GET /index" do
    test "redirects if not logged in", %{conn: conn} do
      conn = conn |> get(~p"/users/subscriptions")
      assert redirected_to(conn) == "/users/log_in"
    end

    test "renders index page", %{user: user, conn: conn} do
      conn = conn |> log_in_user(user) |> get(~p"/users/subscriptions")
      assert html_response(conn, 200) =~ "Benachrichtigungen bearbeiten"
    end

    test "renders a map with the radius of each subscription", %{user: user, conn: conn} do
      {:ok, _subscription} = Accounts.subscribe(user, %{lat: 52.51, lng: 13.2679})

      html = conn |> log_in_user(user) |> get(~p"/users/subscriptions") |> html_response(200)

      assert html =~
               ~r/data-subscription-map data-lat="52.51" data-lng="13.2679" data-radius="\d+"/

      refute html =~ "phx-hook"
    end
  end

  describe "POST /users/subscriptions/:id" do
    test "updates the subscription", %{user: user, conn: conn} do
      {:ok, subscription} =
        Accounts.subscribe(user, %{lat: 52.52329675804731, lng: 13.445322017049648, radius: 4000})

      conn =
        conn
        |> log_in_user(user)
        |> put(
          ~p"/users/subscriptions/#{subscription.id}",
          %{"subscription" => %{"radius" => 1000, "lat" => "50", "lng" => "12"}}
        )

      assert redirected_to(conn) == "/users/subscriptions"

      sub = Accounts.get_subscription_by_id(user, subscription.id)

      assert sub.point == %Geo.Point{
               coordinates: {50, 12},
               properties: %{},
               srid: 4326
             }

      assert sub.radius == 1000
      assert sub.user_id == user.id
    end

    test "rejects an update if the user is wrong", %{user: user, conn: conn} do
      {:ok, subscription} =
        Accounts.subscribe(user, %{lat: 52.52329675804731, lng: 13.445322017049648, radius: 4000})

      conn =
        conn
        |> log_in_user(user_fixture())
        |> put(
          ~p"/users/subscriptions/#{subscription.id}",
          %{"subscription" => %{"radius" => 1000, "lat" => "50", "lng" => "12"}}
        )

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Aktualisierung fehlgeschlagen"
      assert redirected_to(conn) == "/users/subscriptions"
      sub = Accounts.get_subscription_by_id(user, subscription.id)
      assert sub.radius == 4000
    end
  end

  describe "DELETE /users/subscriptions/:id" do
    test "delete the subscription", %{user: user, conn: conn} do
      {:ok, subscription} =
        Accounts.subscribe(user, %{lat: 52.52329675804731, lng: 13.445322017049648, radius: 4000})

      conn =
        conn
        |> log_in_user(user)
        |> delete(~p"/users/subscriptions/#{subscription.id}")

      assert redirected_to(conn) == "/users/subscriptions"

      assert Accounts.get_subscription_by_id(user, subscription.id) == nil
    end

    test "does not delete the subscription if the user is wrong", %{user: user, conn: conn} do
      {:ok, subscription} =
        Accounts.subscribe(user, %{lat: 52.52329675804731, lng: 13.445322017049648, radius: 4000})

      conn =
        conn
        |> log_in_user(user_fixture())
        |> delete(~p"/users/subscriptions/#{subscription.id}")

      assert redirected_to(conn) == "/users/subscriptions"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Löschen fehlgeschlagen"
      assert Accounts.get_subscription_by_id(user, subscription.id) != nil
    end
  end
end
