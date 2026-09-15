defmodule Hierbautberlin.NotifySubscription do
  import Ecto.Query, warn: false
  require Logger

  alias Hierbautberlin.Accounts.User
  alias Hierbautberlin.{Accounts, Repo}
  alias Hierbautberlin.GeoData
  alias Hierbautberlin.GeoData.{GeoItem, NewsItem}
  alias HierbautberlinWeb.Email

  # A source that brings more new items in one import was imported again (e.g.
  # its ids changed or it was added), those items are no news for subscribers.
  @bulk_import_limit 200

  def notify_changes_since(since, opts \\ []) do
    skipped_sources =
      bulk_import_sources(since, Keyword.get(opts, :bulk_import_limit, @bulk_import_limit))

    if skipped_sources != [] do
      Logger.warning(
        "Not notifying about the new items of the sources #{inspect(skipped_sources)}"
      )
    end

    Repo.transaction(
      fn ->
        get_users_with_subscriptions()
        |> Stream.map(&process_user(&1, since, skipped_sources))
        |> Stream.run()
      end,
      timeout: :infinity
    )
  end

  defp bulk_import_sources(since, limit) do
    for schema <- [GeoItem, NewsItem],
        source_id <-
          Repo.all(
            from item in schema,
              where: item.inserted_at >= ^since,
              group_by: item.source_id,
              having: count(item.id) > ^limit,
              select: item.source_id
          ),
        uniq: true,
        do: source_id
  end

  defp process_user(user, since, skipped_sources) do
    user = Accounts.with_subscriptions(user)

    locations = map_subscriptions(user.subscriptions)

    items =
      (GeoData.get_geo_items_for_locations_since(locations, since) ++
         GeoData.get_news_items_for_locations_since(locations, since))
      |> Enum.reject(&(&1.source_id in skipped_sources))

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
