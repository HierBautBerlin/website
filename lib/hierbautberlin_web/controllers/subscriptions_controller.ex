defmodule HierbautberlinWeb.SubscriptionsController do
  use HierbautberlinWeb, :controller

  alias Hierbautberlin.Accounts

  def index(%{assigns: %{current_user: current_user}} = conn, _params) do
    current_user = Accounts.with_subscriptions(current_user)

    render(conn, "index.html",
      page_title: "Benachrichtigungen bearbeiten",
      current_user: current_user
    )
  end

  def update(%{assigns: %{current_user: current_user}} = conn, %{
        "id" => id,
        "subscription" => subscription_params
      }) do
    subscription = Accounts.get_subscription_by_id(current_user, id)

    if subscription == nil do
      conn
      |> put_flash(:error, "Aktualisierung fehlgeschlagen")
      |> redirect(to: Routes.subscriptions_path(conn, :index))
    else
      case Accounts.update_subscription(subscription, subscription_params) do
        {:ok, _user} ->
          conn
          |> put_flash(:info, "Ort erfolgreich aktualisiert.")
          |> redirect(to: Routes.subscriptions_path(conn, :index))

        {:error, _changeset} ->
          current_user = Accounts.with_subscriptions(current_user)

          conn
          |> put_flash(:error, "Aktualisierung fehlgeschlagen")
          |> render("index.html",
            current_user: current_user,
            page_title: "Benachrichtigungen bearbeiten"
          )
      end
    end
  end

  def delete(%{assigns: %{current_user: current_user}} = conn, %{"id" => id}) do
    subscription = Accounts.get_subscription_by_id(current_user, id)

    if subscription == nil do
      conn
      |> put_flash(:error, "Löschen fehlgeschlagen")
      |> redirect(to: Routes.subscriptions_path(conn, :index))
    else
      Accounts.delete_subscription(subscription)

      conn
      |> put_flash(:info, "Ort gelöscht.")
      |> redirect(to: Routes.subscriptions_path(conn, :index))
    end
  end
end
