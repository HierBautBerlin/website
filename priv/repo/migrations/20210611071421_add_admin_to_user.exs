defmodule Hierbautberlin.Repo.Migrations.AddAdminToUser do
  use Ecto.Migration

  def change do
    create_query = "CREATE TYPE user_role AS ENUM ('user', 'moderator', 'admin')"
    drop_query = "DROP TYPE user_role"
    execute(create_query, drop_query)

    alter table(:users) do
      add :role, :user_role, default: "user"
    end
  end
end
