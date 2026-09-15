defmodule Hierbautberlin.GeoData.GeoMapItem do
  @moduledoc """
  An entry of the list next to the map, either a geo item or a news item.
  """
  defstruct [
    :type,
    :id,
    :title,
    :subtitle,
    :description,
    :newest_date,
    :source,
    :url,
    :participation_open,
    :item
  ]
end
