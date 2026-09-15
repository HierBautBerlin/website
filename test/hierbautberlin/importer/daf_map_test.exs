defmodule Hierbautberlin.Importer.DafMapTest do
  use Hierbautberlin.DataCase

  alias Hierbautberlin.Importer.DafMap

  defmodule ImportMock do
    def get!(url, ["User-Agent": "hierbautberlin.de", "X-Requested-By": "dafmapV2"], _opts) do
      send(self(), {:requested, url})

      file =
        case url do
          "https://dafmap.de/serve/projects/berlin" -> "projects.json"
          "https://dafmap.de/serve/project/" <> id -> "project_#{id}.json"
        end

      %{body: File.read!("test/support/data/daf_map/#{file}"), headers: [], status_code: 200}
    end
  end

  describe "import/1" do
    test "basic import of daf map data" do
      {:ok, result} = DafMap.import(ImportMock)

      assert length(result) == 5

      area = Enum.find(result, &(&1.external_id == "8386")) |> Repo.preload(:source)
      assert area.title == "„27 ha Möglichkeiten“ Hohenschönhausen (VISION)"
      assert area.description == nil
      assert %Geo.Polygon{srid: 4326} = area.geometry
      assert area.geo_point == %Geo.Point{coordinates: {13.504522, 52.544105}, srid: 4326}
      assert area.url == "https://dafmap.de/berlin?id=8386&mt=0&zoom=17"
      assert area.date_updated == ~U[2022-11-03 13:44:53Z]
      assert area.state == nil
      assert area.source.short_name == "DAF_MAP"

      assert area.additional_link ==
               "https://www.deutsches-architekturforum.de/thread/11397-lichtenberg-kleinere-projekte/?postID=729177#post729177"

      assert area.additional_link_name == "Deutsches Architekturforum"

      building = Enum.find(result, &(&1.external_id == "8978"))
      assert building.state == "under_construction"
      assert building.date_start == ~U[2025-05-31 00:00:00Z]
      assert building.date_end == ~U[2026-12-30 00:00:00Z]
      assert building.geometry == nil

      # a placeholder image is not a link to the forum
      finished = Enum.find(result, &(&1.external_id == "7272"))
      assert finished.state == "finished"
      assert finished.additional_link == nil
    end

    test "only loads the details of changed projects" do
      {:ok, _result} = DafMap.import(ImportMock)
      assert_received {:requested, "https://dafmap.de/serve/project/8978"}

      {:ok, result} = DafMap.import(ImportMock)
      refute_received {:requested, "https://dafmap.de/serve/project/8978"}

      # description and links are kept
      area = Enum.find(result, &(&1.external_id == "8386"))
      assert area.additional_link_name == "Deutsches Architekturforum"
    end
  end
end
