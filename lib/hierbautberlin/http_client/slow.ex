defmodule Hierbautberlin.HTTPClient.Slow do
  @moduledoc """
  `Hierbautberlin.HTTPClient` with a pause before every request, for imports
  that read many pages. berlin.de answers with redirect loops when requests come
  in too fast.
  """

  def get!(url, headers \\ [], opts \\ []) do
    Process.sleep(700)
    Hierbautberlin.HTTPClient.get!(url, headers, opts)
  end
end
