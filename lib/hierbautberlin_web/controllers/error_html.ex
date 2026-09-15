defmodule HierbautberlinWeb.ErrorHTML do
  @moduledoc """
  Invoked by the endpoint in case a request results in an error.
  """
  use HierbautberlinWeb, :html

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.html" becomes
  # "Not Found".
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
