defmodule HierbautberlinWeb.AboutController do
  use HierbautberlinWeb, :controller

  alias Hierbautberlin.GeoData

  @description "Hier Baut Berlin sammelt Bauprojekte, Bebauungspläne, Beteiligungsverfahren " <>
                 "und Meldungen der Stadt Berlin und zeigt sie auf einer Karte. " <>
                 "Wer dahinter steckt und woher die Daten kommen."

  def index(conn, _params) do
    render(conn, :index,
      page_title: "Über uns",
      meta_description: @description,
      ogtags: %{"og:description" => @description, "twitter:description" => @description},
      sources: GeoData.list_sources()
    )
  end
end
