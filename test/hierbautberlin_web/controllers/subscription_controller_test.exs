defmodule HierbautberlinWeb.SubscriptionControllerTest do
  use HierbautberlinWeb.ConnCase, async: true

  alias Hierbautberlin.Accounts
  import Hierbautberlin.AccountsFixtures

  setup do
    %{user: user_fixture()}
  end

  describe "GET /index" do
    test "redirects if not logged in", %{conn: conn} do
      conn = conn |> get(Routes.subscriptions_path(conn, :index))
      assert redirected_to(conn) == "/users/log_in"
    end

    test "renders index page", %{user: user, conn: conn} do
      conn = conn |> log_in_user(user) |> get(Routes.subscriptions_path(conn, :index))
      assert html_response(conn, 200) =~ "Benachrichtigungen bearbeiten"
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
          Routes.subscriptions_path(conn, :update, subscription.id),
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
          Routes.subscriptions_path(conn, :update, subscription.id),
          %{"subscription" => %{"radius" => 1000, "lat" => "50", "lng" => "12"}}
        )

      assert get_flash(conn, :error) == "Aktualisierung fehlgeschlagen"
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
        |> delete(Routes.subscriptions_path(conn, :delete, subscription.id))

      assert redirected_to(conn) == "/users/subscriptions"

      assert Accounts.get_subscription_by_id(user, subscription.id) == nil
    end

    test "does not delete the subscription if the user is wrong", %{user: user, conn: conn} do
      {:ok, subscription} =
        Accounts.subscribe(user, %{lat: 52.52329675804731, lng: 13.445322017049648, radius: 4000})

      conn =
        conn
        |> log_in_user(user_fixture())
        |> delete(Routes.subscriptions_path(conn, :delete, subscription.id))

      assert redirected_to(conn) == "/users/subscriptions"

      assert get_flash(conn, :error) == "Löschen fehlgeschlagen"
      assert Accounts.get_subscription_by_id(user, subscription.id) != nil
    end
  end
end
