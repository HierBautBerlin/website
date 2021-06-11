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
        <%= live_patch raw("&times;"), "aria-label": "close", to: @return_to, class: "phx-modal-close" %>
        <div class="phx-modal-content">
          <%= live_component @socket, @component, @opts %>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("close", _, socket) do
    {:noreply, push_patch(socket, to: socket.assigns.return_to)}
  end
end
