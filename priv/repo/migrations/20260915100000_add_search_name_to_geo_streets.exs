defmodule Hierbautberlin.Repo.Migrations.AddSearchNameToGeoStreets do
  use Ecto.Migration

  # The street search compares normalized names, see GeoData.search_street/1:
  # lower case without accents, "straße"/"strasse"/"str." as "str" and
  # everything that is not a letter or digit as a single space.
  # "Karl-Marx-Straße" -> "karl marx str"
  def up do
    execute """
    CREATE FUNCTION search_normalize(value text) RETURNS text
    LANGUAGE sql STABLE SET search_path = public AS $$
      SELECT trim(regexp_replace(
        regexp_replace(lower(public.unaccent(value)), 'str(asse|\\.)?', 'str', 'g'),
        '[^a-z0-9]+', ' ', 'g'
      ))
    $$
    """

    alter table(:geo_streets) do
      add :search_name, :text
    end

    execute """
    CREATE FUNCTION geo_streets_search_name_update() RETURNS trigger
    LANGUAGE plpgsql SET search_path = public AS $$
      BEGIN
        NEW.search_name := search_normalize(NEW.name);
        RETURN NEW;
      END
    $$
    """

    execute """
    CREATE TRIGGER geo_streets_search_name_trigger BEFORE INSERT OR UPDATE OF name
    ON geo_streets FOR EACH ROW EXECUTE FUNCTION geo_streets_search_name_update()
    """

    execute "UPDATE geo_streets SET search_name = search_normalize(name)"

    # replaced by search_name
    execute "DROP TRIGGER street_name_fulltext_search_trigger ON geo_streets"
    execute "DROP FUNCTION street_name_fulltext_search_update()"
    execute "DROP INDEX street_name_fulltext_search"

    alter table(:geo_streets) do
      remove :fulltext_search
    end
  end

  def down do
    alter table(:geo_streets) do
      add :fulltext_search, :tsvector
    end

    execute "CREATE INDEX street_name_fulltext_search ON geo_streets USING gin(fulltext_search)"

    execute """
    CREATE FUNCTION street_name_fulltext_search_update() RETURNS trigger AS $$
      begin
        new.fulltext_search := to_tsvector('german'::regconfig, unaccent(new.name));
        return new;
      end
    $$ LANGUAGE plpgsql
    """

    execute """
    CREATE TRIGGER street_name_fulltext_search_trigger BEFORE INSERT OR UPDATE
    ON geo_streets FOR EACH ROW EXECUTE PROCEDURE street_name_fulltext_search_update()
    """

    execute "UPDATE geo_streets SET fulltext_search = to_tsvector('german'::regconfig, unaccent(name))"

    execute "DROP TRIGGER geo_streets_search_name_trigger ON geo_streets"
    execute "DROP FUNCTION geo_streets_search_name_update()"

    alter table(:geo_streets) do
      remove :search_name
    end

    execute "DROP FUNCTION search_normalize(text)"
  end
end
