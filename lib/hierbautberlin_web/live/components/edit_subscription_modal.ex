defmodule HierbautberlinWeb.Components.EditSubscriptionModal do
  use HierbautberlinWeb, :live_component

  alias Hierbautberlin.Accounts

  @impl true
  def handle_event(
        "save",
        %{"subscription" => %{"radius" => radius}},
        %{assigns: %{id: id, current_user: current_user}} = socket
      ) do
    subscription = Accounts.get_subscription_by_id(current_user, id)
    {:ok, subscription} = Accounts.update_subscription(subscription, %{radius: radius})
    send(self(), {"update_subscription", subscription})
    send(self(), "close_edit_subscription")
    {:noreply, socket}
  end
end
