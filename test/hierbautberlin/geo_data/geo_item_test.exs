defmodule Hierbautberlin.GeoData.GeoItemTest do
  use Hierbautberlin.DataCase

  alias Hierbautberlin.GeoData.GeoItem

  describe "newest_date/1" do
    test "it returns date_update if it's the newest" do
      item =
        insert(:geo_item, %{
          date_start: Timex.parse!("2020-10-01", "{YYYY}-{0M}-{0D}"),
          date_end: Timex.parse!("2020-10-02", "{YYYY}-{0M}-{0D}"),
          date_updated: Timex.parse!("2020-10-03", "{YYYY}-{0M}-{0D}")
        })

      assert ~U[2020-10-03 00:00:00Z] == GeoItem.newest_date(item)
    end

    test "it returns date_start if it's the newest" do
      item =
        insert(:geo_item, %{
          date_start: Timex.parse!("2020-10-04", "{YYYY}-{0M}-{0D}"),
          date_end: Timex.parse!("2020-10-02", "{YYYY}-{0M}-{0D}"),
          date_updated: Timex.parse!("2020-10-03", "{YYYY}-{0M}-{0D}")
        })

      assert ~U[2020-10-04 00:00:00Z] == GeoItem.newest_date(item)
    end

    test "it returns date_end if it's the newest" do
      item =
        insert(:geo_item, %{
          date_start: Timex.parse!("2020-10-01", "{YYYY}-{0M}-{0D}"),
          date_end: Timex.parse!("2020-10-05", "{YYYY}-{0M}-{0D}"),
          date_updated: Timex.parse!("2020-10-03", "{YYYY}-{0M}-{0D}")
        })

      assert ~U[2020-10-05 00:00:00Z] == GeoItem.newest_date(item)
    end

    test "it returns the date closest to now if all dates are in the future" do
      item =
        insert(:geo_item, %{
          date_start: Timex.parse!("2030-10-01", "{YYYY}-{0M}-{0D}"),
          date_end: Timex.parse!("2030-10-05", "{YYYY}-{0M}-{0D}"),
          date_updated: Timex.parse!("2030-10-03", "{YYYY}-{0M}-{0D}")
        })

      assert ~U[2030-10-01 00:00:00Z] == GeoItem.newest_date(item)
    end

    test "it returns nil if no date is present" do
      item = insert(:geo_item)
      assert nil == GeoItem.newest_date(item)
    end
  end
end
