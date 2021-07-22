defmodule Hierbautberlin.Repo.Migrations.AddIndexes do
  use Ecto.Migration

  def change do
    create index(:geo_items, [:hidden])
    create index(:news_items, [:hidden])

    execute("CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;")

    alter table(:geo_streets) do
      add :fulltext_search, :tsvector
    end

    execute("CREATE INDEX street_name_fulltext_search ON geo_streets USING gin(fulltext_search);")
    execute("CREATE EXTENSION IF NOT EXISTS unaccent;")

    add_trigger_function()
    activate_trigger()
    trigger_existing_records()
  end

  defp add_trigger_function do
    execute("""
      CREATE FUNCTION street_name_fulltext_search_update() RETURNS trigger AS $$
          begin
            new.fulltext_search := to_tsvector('german'::regconfig, unaccent(new.name));
            return new;
          end
      $$ LANGUAGE plpgsql;
    """)
  end

  defp activate_trigger do
    execute("""
     CREATE TRIGGER street_name_fulltext_search_trigger BEFORE INSERT OR UPDATE
         ON geo_streets FOR EACH ROW EXECUTE PROCEDURE street_name_fulltext_search_update();
    """)
  end

  defp trigger_existing_records do
    execute("UPDATE geo_streets set name=name;")
  end
end
