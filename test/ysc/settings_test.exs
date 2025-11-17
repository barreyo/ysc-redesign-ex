defmodule Ysc.SettingsTest do
  use Ysc.DataCase, async: false
  alias Ysc.Settings
  alias Ysc.SiteSettings.SiteSetting

  setup do
    # Clear out any existing settings and cache before each test
    Repo.delete_all(SiteSetting)
    Settings.clear_cache()
    :ok
  end

  describe "settings/0" do
    test "returns all settings ordered by id desc" do
      # Clear cache before test to ensure fresh state
      Settings.clear_cache()

      setting1 = %SiteSetting{name: "setting1", value: "value1"} |> Repo.insert!()
      # Add a small delay to ensure setting2 gets a later ULID
      Process.sleep(1)
      setting2 = %SiteSetting{name: "setting2", value: "value2"} |> Repo.insert!()

      # Clear cache again to force fresh query from DB
      Settings.clear_cache()

      settings = Settings.settings()
      assert length(settings) == 2
      # Since setting2 was created after setting1, its ID should be "greater" (newer ULID)
      # and thus come first when ordered by desc
      # Check that both settings are present and setting2 comes first
      assert Enum.map(settings, & &1.id) == [setting2.id, setting1.id]
    end

    test "uses cache when available" do
      # Clear cache before test to ensure clean state
      Settings.clear_cache()

      setting = %SiteSetting{name: "test", value: "test"} |> Repo.insert!()

      # First call populates cache
      [cached_setting] = Settings.settings()
      assert cached_setting.id == setting.id

      # Delete from DB but should still return from cache
      Repo.delete!(setting)
      assert [^cached_setting] = Settings.settings()
    end
  end

  describe "get_setting/1" do
    test "returns setting value" do
      %SiteSetting{name: "test_setting", value: "test_value"} |> Repo.insert!()
      assert Settings.get_setting("test_setting") == "test_value"
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

      # Update DB directly (bypassing Settings.update_setting which would update cache)
      setting
      |> Ecto.Changeset.change(value: "new")
      |> Repo.update!()

      # Should still return cached value since we didn't use Settings.update_setting
      assert Settings.get_setting("cached") == "old"
    end
  end

  describe "update_setting/2" do
    test "updates setting value" do
      setting = %SiteSetting{name: "test", value: "old"} |> Repo.insert!()

      assert {:ok, updated} = Settings.update_setting("test", "new")
      assert updated.value == "new"

      # Verify DB was updated
      assert Repo.get!(SiteSetting, setting.id).value == "new"
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
    end
  end
end
