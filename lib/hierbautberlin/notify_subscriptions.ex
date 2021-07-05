defmodule Hierbautberlin.NotifySubscription do
  import Ecto.Query, warn: false
  alias Hierbautberlin.Accounts.User
  alias Hierbautberlin.{Accounts, Repo}
  alias Hierbautberlin.GeoData.{GeoItem, NewsItem}
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

    items =
      get_geo_items_for_subscriptions_since(user.subscriptions, since) ++
        get_news_items_for_subscriptions_since(user.subscriptions, since)

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

  defp get_geo_items_for_subscriptions_since(subscriptions, since) do
    conditions = false

    conditions =
      Enum.reduce(subscriptions, conditions, fn subscription, conditions ->
        %{coordinates: {lat, lng}} = subscription.point

        radius = subscription.radius

        filter_conditions =
          dynamic(
            [item],
            fragment(
              "ST_DWITHIN(COALESCE(geometry, geo_point), ST_MakePoint(?, ?)::geography, ?)",
              ^lng,
              ^lat,
              ^radius
            )
          )

        if conditions do
          dynamic([item], ^filter_conditions or ^conditions)
        else
          dynamic([item], ^filter_conditions)
        end
      end)

    query =
      from item in GeoItem,
        where: item.inserted_at >= ^since,
        where: ^conditions

    Repo.all(query)
  end

  defp get_news_items_for_subscriptions_since(subscriptions, since) do
    conditions = false

    conditions =
      Enum.reduce(subscriptions, conditions, fn subscription, conditions ->
        %{coordinates: {lat, lng}} = subscription.point

        radius = subscription.radius

        filter_conditions =
          dynamic(
            [item],
            fragment(
              "(ST_DWITHIN(geometries, ST_MakePoint(?, ?)::geography, ?) OR ST_DWITHIN(geo_points, ST_MakePoint(?, ?)::geography, ?))",
              ^lng,
              ^lat,
              ^radius,
              ^lng,
              ^lat,
              ^radius
            )
          )

        if conditions do
          dynamic([item], ^filter_conditions or ^conditions)
        else
          dynamic([item], ^filter_conditions)
        end
      end)

    query =
      from item in NewsItem,
        where: item.inserted_at >= ^since,
        where: ^conditions

    Repo.all(query)
  end
end
