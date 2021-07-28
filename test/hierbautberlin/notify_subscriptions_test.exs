defmodule Hierbautberlin.NotifySubscriptionTest do
  use Hierbautberlin.DataCase, async: false
  use Bamboo.Test
  import Hierbautberlin.AccountsFixtures

  alias Ecto.Adapters.SQL
  alias Hierbautberlin.Accounts
  alias Hierbautberlin.NotifySubscription

  describe "notify_changes_since/1" do
    setup do
      user_fixture()
      user = user_fixture()

      insert(:geo_item,
        title: "Distant Point Item",
        geo_point: %Geo.Point{
          coordinates: {13, 52},
          properties: %{},
          srid: 4326
        }
      )

      old_item =
        insert(:geo_item,
          title: "Old Point Item",
          geo_point: %Geo.Point{
            coordinates: {13.3789047176, 52.51650032279},
            properties: %{},
            srid: 4326
          }
        )

      SQL.query!(
        Hierbautberlin.Repo,
        "UPDATE geo_items SET inserted_at = '2010-01-01 4:30' WHERE id= $1",
        [old_item.id]
      )

      insert(:geo_item,
        title: "Point Item",
        geo_point: %Geo.Point{
          coordinates: {13.26805, 52.525},
          properties: %{},
          srid: 4326
        }
      )

      insert(:geo_item,
        title: "Polygon Item",
        geometry: %Geo.MultiPolygon{
          coordinates: [
            [
              [
                {13.26805, 52.525},
                {13.26805, 52.530},
                {13.26810, 52.530},
                {13.26805, 52.525}
              ]
            ]
          ]
        }
      )

      Accounts.subscribe(user, %{lat: 52.51, lng: 13.2679})

      insert(:news_item)
      old_news = insert(:news_item, title: "Old News")

      SQL.query!(
        Hierbautberlin.Repo,
        "UPDATE news_items SET inserted_at = '2010-01-01 4:30' WHERE id= $1",
        [old_news.id]
      )

      %{user: user}
    end

    test "it will send an email with all the imporant new data points", %{user: user} do
      NotifySubscription.notify_changes_since(Timex.parse!("2013-03-05", "{YYYY}-{0M}-{0D}"))

      assert_delivered_email_matches(%{to: user_email, text_body: text_body})
      assert user_email == [{nil, user.email}]
      assert text_body =~ "Point Item"
      assert text_body =~ "Polygon Item"
      assert text_body =~ "This is a nice title"
      refute text_body =~ "Distant Point Item"
      refute text_body =~ "Old Point Item"
      refute text_body =~ "Old News"
    end
  end
end
