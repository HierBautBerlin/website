defmodule Hierbautberlin.GeoDataTest do
  use Hierbautberlin.DataCase

  alias Hierbautberlin.GeoData

  describe "get_source/1" do
    test "gets a source by it's id" do
      data = insert(:source)

      geo_data = GeoData.get_source!(data.id)
      assert geo_data.short_name == "TEST"
      assert geo_data.name == "City Source"
      assert geo_data.url == "https://city.example.com"
      assert geo_data.copyright == "Example"
    end

    test "raises no result if id is not found" do
      assert_raise Ecto.NoResultsError, fn -> GeoData.get_source!(2_131_231) end
    end
  end

  describe "upsert_source/1" do
    test "creates and updates a source" do
      {:ok, insert} =
        GeoData.upsert_source(%{
          short_name: "TEST",
          name: "City Source",
          url: "https://city.example.com",
          copyright: "Example"
        })

      assert insert.short_name == "TEST"
      assert insert.name == "City Source"
      assert insert.url == "https://city.example.com"
      assert insert.copyright == "Example"

      {:ok, upsert} =
        GeoData.upsert_source(%{
          short_name: "TEST",
          name: "Village Source",
          url: "https://village.example.com",
          copyright: "MIT"
        })

      assert insert.id == upsert.id

      geo_data = GeoData.get_source!(upsert.id)
      assert geo_data.short_name == "TEST"
      assert geo_data.name == "Village Source"
      assert geo_data.url == "https://village.example.com"
      assert geo_data.copyright == "MIT"
    end
  end

  describe "get_geo_item!/1" do
    test "it returns a geo item" do
      source = insert(:source)

      {:ok, item} =
        GeoData.create_geo_item(%{
          source_id: source.id,
          external_id: "12354",
          title: "Example Item"
        })

      geo_item = GeoData.get_geo_item!(item.id)

      assert geo_item.id == item.id
      assert geo_item.source_id == source.id
      assert geo_item.external_id == "12354"
      assert geo_item.title == "Example Item"
    end
  end

  describe "change_geo_item!/1" do
    test "it returns a GeoItem changeset" do
      source = insert(:source)

      {:ok, item} =
        GeoData.create_geo_item(%{
          source_id: source.id,
          external_id: "12354",
          title: "Example Item"
        })

      assert %Ecto.Changeset{} = GeoData.change_geo_item(item)
    end
  end

  describe "upsert_geo_item/1" do
    test "it creates and updates a GeoItem" do
      source = insert(:source)

      {:ok, item} =
        GeoData.upsert_geo_item(%{
          source_id: source.id,
          external_id: "12354",
          title: "Example Item",
          subtitle: "Hm..."
        })

      geo_item = GeoData.get_geo_item!(item.id)

      assert geo_item.id == item.id
      assert geo_item.source_id == source.id
      assert geo_item.external_id == "12354"
      assert geo_item.title == "Example Item"

      {:ok, updated_item} =
        GeoData.upsert_geo_item(%{
          source_id: source.id,
          external_id: "12354",
          title: "New Example",
          subtitle: "Amazing Title"
        })

      assert updated_item.id == item.id
      assert updated_item.source_id == source.id
      assert updated_item.external_id == "12354"
      assert updated_item.title == "New Example"
      assert updated_item.subtitle == "Amazing Title"
    end
  end
end
