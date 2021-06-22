defmodule Hierbautberlin.Accounts.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  schema "subscriptions" do
    belongs_to :user, Hierbautberlin.Accounts.User
    field :radius, :integer, default: 2000
    field :point, Geo.PostGIS.Geometry
    field :lat, :float, virtual: true
    field :lng, :float, virtual: true
    timestamps()
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:lat, :lng, :radius])
    |> transform_lat_lng()
  end

  def changeset_for_user(subscription, user, attrs) do
    subscription
    |> cast(attrs, [:lat, :lng, :radius])
    |> put_change(:user_id, user.id)
    |> transform_lat_lng()
  end

  defp transform_lat_lng(changeset) do
    if get_field(changeset, :lat) && get_field(changeset, :lng) do
      point = %Geo.Point{
        coordinates: {get_field(changeset, :lat), get_field(changeset, :lng)},
        properties: %{},
        srid: 4326
      }

      put_change(changeset, :point, point)
    else
      changeset
    end
  end
end
