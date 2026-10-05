defmodule Hierbautberlin.Repo.Migrations.ClearIncompletePressTexts do
  use Ecto.Migration

  def up do
    # Press releases whose article page could not be fetched were stored with
    # only title and teaser as text. Without a text the importer and the
    # reanalysis fetch the article again.
    execute("""
    UPDATE news_items
    SET full_text = NULL
    WHERE source_id IN (SELECT id FROM sources WHERE short_name = 'BERLIN_PRESSE')
      AND btrim(full_text, E' \\n\\t') =
          btrim(coalesce(title, '') || E'\\n' || coalesce(content, ''), E' \\n\\t')
    """)
  end

  def down, do: :ok
end
