defmodule HierbautberlinWeb.ModalComponent do
  use HierbautberlinWeb, :live_component

  @impl true
  def render(assigns) do
    ~L"""
    <div id="<%= @id %>" class="phx-modal"
      phx-capture-click="close"
      phx-window-keydown="close"
      phx-key="escape"
      phx-target="#<%= @id %>"
      phx-page-loading>

      <div class="phx-modal-inner">
        <%= if @return_to do %>
          <%= live_patch raw("&times;"), "aria-label": "close", to: @return_to, class: "phx-modal-close" %>
        <% end %>
        <%= if @message_on_close do %>
          <button phx-click="close" phx-target="<%= @myself %>" class="phx-modal-close">&times;</button>
        <% end %>
        <div class="phx-modal-content">
          <%= live_component @socket, @component, @opts %>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("close", _, %{assigns: %{message_on_close: message_on_close}} = socket)
      when not is_nil(message_on_close) do
    send(self(), message_on_close)
    {:noreply, socket}
  end

  @impl true
  def handle_event("close", _, %{assigns: %{return_to: return_to}} = socket) do
    {:noreply, push_patch(socket, to: return_to)}
  end
end
