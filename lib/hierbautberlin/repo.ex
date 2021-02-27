defmodule Hierbautberlin.Repo do
  use Ecto.Repo,
    otp_app: :hierbautberlin,
    adapter: Ecto.Adapters.Postgres
end
