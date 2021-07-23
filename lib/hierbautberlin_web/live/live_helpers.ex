defmodule HierbautberlinWeb.LiveHelpers do
  import Phoenix.LiveView.Helpers

  @doc """
  Renders a component inside the `HierbautberlinWeb.ModalComponent` component.

  The rendered modal receives a `:return_to` option to properly update
  the URL when the modal is closed.

  ## Examples

      <%= live_modal @socket, HierbautberlinWeb.UserLive.FormComponent,
        id: @user.id || :new,
        action: @live_action,
        user: @user,
        return_to: Routes.user_index_path(@socket, :index) %>
  """
  def live_modal(socket, component, opts) do
    path = Keyword.get(opts, :return_to)
    message_on_close = Keyword.get(opts, :message_on_close)

    modal_opts = [
      id: :modal,
      return_to: path,
      message_on_close: message_on_close,
      component: component,
      current_user: Keyword.get(opts, :current_user),
      opts: opts
    ]

    live_component(socket, HierbautberlinWeb.ModalComponent, modal_opts)
  end

  def is_street_duplicate?(name, streets) do
    Enum.count_until(
      streets,
      fn street ->
        street.name == name
      end,
      2
    ) > 1
  end
end
