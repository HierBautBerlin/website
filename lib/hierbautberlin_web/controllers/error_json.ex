defmodule HierbautberlinWeb.ErrorJSON do
  @moduledoc """
  Invoked by the endpoint in case a JSON request results in an error.
  """

  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
