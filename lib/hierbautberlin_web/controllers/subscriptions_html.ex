defmodule HierbautberlinWeb.SubscriptionsHTML do
  use HierbautberlinWeb, :html

  embed_templates "subscriptions_html/*"

  def radius_options do
    ["500 M": 500, "1 KM": 1000, "2 KM": 2000, "4 KM": 4000, "8 KM": 8000, "10 KM": 10_000]
  end
end
