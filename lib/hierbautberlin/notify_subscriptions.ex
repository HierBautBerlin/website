defmodule Hierbautberlin.NotifySubscription do
  import Ecto.Query, warn: false
  alias Hierbautberlin.Accounts.User
  alias Hierbautberlin.{Accounts, Repo}
  alias Hierbautberlin.GeoData
  alias HierbautberlinWeb.Email

  def notify_changes_since(since) do
    Repo.transaction(
      fn ->
        get_users_with_subscriptions()
        |> Stream.map(&process_user(&1, since))
        |> Stream.run()
      end,
      timeout: :infinity
    )
  end

  defp process_user(user, since) do
    user = Accounts.with_subscriptions(user)

    locations = map_subscriptions(user.subscriptions)

    items =
      GeoData.get_geo_items_for_locations_since(locations, since) ++
        GeoData.get_news_items_for_locations_since(locations, since)

    if !Enum.empty?(items) do
      Email.new_items_found(user, items)
    end
  end

  defp get_users_with_subscriptions() do
    query =
      from u in User,
        where: u.id in fragment("select distinct user_id from subscriptions")

    Repo.stream(query)
  end

  defp map_subscriptions(subscriptions) do
    subscriptions
    |> Enum.map(fn subscription ->
      %{coordinates: {lat, lng}} = subscription.point
      radius = subscription.radius

      %{
        location: {lat, lng},
        radius: radius
      }
    end)
  end
end
