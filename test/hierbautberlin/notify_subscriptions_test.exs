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
          coordinates: {13.3789047176, 52.51650032279},
          properties: %{},
          srid: 4326
        }
      )

      insert(:geo_item,
        title: "Polygon Item",
        geo_geometry: %Geo.MultiPolygon{
          coordinates: [
            [
              [
                {13.380798423826, 52.5164936040044},
                {13.3806891103893, 52.516743173892},
                {13.3801051997461, 52.5189687524263},
                {13.3800436415096, 52.5189662186233},
                {13.3799820166143, 52.5189643842998},
                {13.3799203664072, 52.5189628999535},
                {13.3798586815915, 52.5189621159569},
                {13.3797969874703, 52.5189616822377},
                {13.380798423826, 52.5164936040044}
              ]
            ]
          ]
        }
      )

      Accounts.subscribe(user, %{lat: 52.51650032279812, lng: 13.378904717640268})

      %{user: user}
    end

    test "it will send an email with all the imporant new data points", %{user: user} do
      NotifySubscription.notify_changes_since(Timex.parse!("2013-03-05", "{YYYY}-{0M}-{0D}"))

      assert_delivered_email_matches(%{to: user_email, text_body: text_body})
      assert user_email == [{nil, user.email}]
      assert text_body =~ "Point Item"
      assert text_body =~ "Polygon Item"
      refute text_body =~ "Distant Point Item"
      refute text_body =~ "Old Point Item"
    end
  end
end
