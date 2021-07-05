defmodule Hierbautberlin.Importer.DafMapTest do
  use Hierbautberlin.DataCase

  alias Hierbautberlin.Importer.DafMap

  defmodule ImportMock do
    def get!(
          "https://www.dafmap.de/d/dafmapgw.py?c=sel&map=berlin",
          ["User-Agent": "hierbautberlin.de", Referer: "https://www.dafmap.de/d/berlin.html"],
          timeout: 60_000,
          recv_timeout: 60_000
        ) do
      {:ok, html} = File.read("./test/support/data/daf_map/feed.json")
      %{body: html, headers: [], status_code: 200}
    end
  end

  describe "import/1" do
    test "basic import of daf map data" do
      result = DafMap.import(ImportMock)

      assert length(result) == 5
      first = List.first(result) |> Repo.preload(:source)

      assert first.description == nil
      assert first.external_id == "7603"

      assert first.geo_geometry == %Geo.Polygon{
               coordinates: [
                 [
                   {13.13438, 52.36896},
                   {13.13152, 52.37064},
                   {13.1315, 52.37103},
                   {13.1344, 52.36935},
                   {13.13686, 52.37099},
                   {13.13738, 52.37078},
                   {13.13438, 52.36896}
                 ]
               ],
               properties: %{},
               srid: 4326
             }

      assert first.geo_point == %Geo.Point{
               coordinates: {13.134411, 52.369165},
               properties: %{},
               srid: 4326
             }

      assert first.date_updated == ~U[2020-08-26 11:46:07Z]
      assert first.participation_open == false
      assert first.source.short_name == "DAF_MAP"
      assert first.state == nil
      assert first.subtitle == nil
      assert first.title == "\"Wohnen am Stern\" - Wohnhochhäuser am Stern-Center"
      assert first.url == "https://www.dafmap.de/d/berlin?id=7603&mt=0&zoom=17"

      assert first.additional_link ==
               "https://www.deutsches-architekturforum.de/thread/226-potsdam-aktuelles-sonstige-meldungen-und-projekte/?postID=665941#post665941"

      assert first.additional_link_name == "Deutsches Architekturforum"
    end
  end
end
