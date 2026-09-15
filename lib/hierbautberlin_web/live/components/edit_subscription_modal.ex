defmodule HierbautberlinWeb.Components.EditSubscriptionModal do
  use HierbautberlinWeb, :live_component

  alias Hierbautberlin.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h3 class="details--content--title">Neue Benachrichtigung</h3>

      <div
        id={"subscription-map-#{@id}"}
        class="map-details details--subscription-map"
        phx-hook="SubscriptionMap"
        data-subscription-map
        data-lat={elem(@subscription.point.coordinates, 0)}
        data-lng={elem(@subscription.point.coordinates, 1)}
        data-radius={@subscription.radius}
      >
        <div class="map-details--map" phx-update="ignore" id={"subscription-map-tiles-#{@id}"}></div>

        <.form
          :let={f}
          for={Accounts.change_subscription(@subscription, %{id: nil})}
          class="map-details--form"
          phx-submit="save"
          phx-target={@myself}
        >
          <p>Sobald ein Eintrag in diesem Radius hinzugefügt wird, wirst du benachrichtigt.</p>
          <label>
            Radius
            <select name={f[:radius].name}>
              {Phoenix.HTML.Form.options_for_select(
                HierbautberlinWeb.SubscriptionsHTML.radius_options(),
                f[:radius].value
              )}
            </select>
          </label>
          <button type="submit" class="button button--small">Aktualisieren</button>
        </.form>
      </div>
    </div>
    """
  end

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
