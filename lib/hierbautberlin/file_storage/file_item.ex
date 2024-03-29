defmodule Hierbautberlin.FileStorage.FileItem do
  use Ecto.Schema
  import Ecto.Changeset

  schema "files" do
    field :name, :string
    field :title, :string
    field :type, :string

    timestamps()
  end

  @doc false
  def changeset(file_item, attrs) do
    file_item
    |> cast(attrs, [:name, :title, :type])
    |> validate_required([:name, :title, :type])
  end
end
