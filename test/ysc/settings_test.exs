defmodule Ysc.SettingsTest do
  use Ysc.DataCase, async: true
  alias Ysc.Settings
  alias Ysc.SiteSettings.SiteSetting

  setup do
    # Clear out any existing settings before each test
    Repo.delete_all(SiteSetting)
    :ok
  end

  describe "settings/0" do
    test "returns all settings ordered by id desc" do
      setting1 = %SiteSetting{name: "setting1", value: "value1"} |> Repo.insert!()
      setting2 = %SiteSetting{name: "setting2", value: "value2"} |> Repo.insert!()

      settings = Settings.settings()
      assert length(settings) == 2
      assert Enum.map(settings, & &1.id) == [setting2.id, setting1.id]

      # Clear cache after test
      Settings.clear_cache()
    end

    test "uses cache when available" do
      setting = %SiteSetting{name: "test", value: "test"} |> Repo.insert!()

      # First call populates cache
      [cached_setting] = Settings.settings()
      assert cached_setting.id == setting.id

      # Delete from DB but should still return from cache
      Repo.delete!(setting)
      assert [^cached_setting] = Settings.settings()

      # Clear cache after test
      Settings.clear_cache()
    end
  end

  describe "get_setting/1" do
    test "returns setting value" do
      %SiteSetting{name: "test_setting", value: "test_value"} |> Repo.insert!()
      assert Settings.get_setting("test_setting") == "test_value"

      # Clear cache after test
      Settings.clear_cache()
    end

    test "raises if setting not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Settings.get_setting("nonexistent")
      end
    end

    test "uses cache when available" do
      setting = %SiteSetting{name: "cached", value: "old"} |> Repo.insert!()

      # First call populates cache
      assert Settings.get_setting("cached") == "old"

      # Update DB but should still return cached value
      setting
      |> Ecto.Changeset.change(value: "updated")
      |> Repo.update!()

      assert Settings.get_setting("cached") == "old"

      # Clear cache after test
      Settings.clear_cache()
    end
  end

  describe "update_setting/2" do
    test "updates setting value" do
      setting = %SiteSetting{name: "test", value: "old"} |> Repo.insert!()

      assert {:ok, updated} = Settings.update_setting("test", "new")
      assert updated.value == "new"

      # Verify DB was updated
      assert Repo.get!(SiteSetting, setting.id).value == "new"

      # Clear cache after test
      Settings.clear_cache()
    end

    test "raises if setting not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Settings.update_setting("nonexistent", "value")
      end
    end

    test "updates caches after successful update" do
      %SiteSetting{name: "cached", value: "old"} |> Repo.insert!()

      # Populate cache
      assert Settings.get_setting("cached") == "old"
      assert [%{value: "old"}] = Settings.settings()

      # Update should refresh caches
      {:ok, _} = Settings.update_setting("cached", "new")

      assert Settings.get_setting("cached") == "new"
      assert [%{value: "new"}] = Settings.settings()

      # Clear cache after test
      Settings.clear_cache()
    end
  end
end
