defmodule Ysc.Settings do
  @moduledoc """
  Context module for managing site settings.

  Provides functions for retrieving and caching application-wide site settings.
  """
  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.SiteSettings.SiteSetting

  # Cache all settings on app startup
  @settings_cache_key "all-site-settings"

  def start_link do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(state) do
    # Warm up cache on startup
    cache_all_settings()
    {:ok, state}
  end

  defp cache_all_settings do
    settings =
      Repo.all(
        from s in SiteSetting,
          order_by: [{:desc, :id}]
      )

    # Cache the full settings list
    Cachex.put(:ysc_cache, @settings_cache_key, settings)

    # Cache individual settings
    Enum.each(settings, fn setting ->
      Cachex.put(:ysc_cache, setting_cache_key(setting.name), setting.value)
    end)
  end

  def settings() do
    case Cachex.get(:ysc_cache, @settings_cache_key) do
      {:ok, nil} ->
        settings =
          Repo.all(
            from s in SiteSetting,
              order_by: [{:desc, :id}]
          )

        Cachex.put(:ysc_cache, @settings_cache_key, settings)
        settings

      {:ok, settings} ->
        settings

      _ ->
        Repo.all(
          from s in SiteSetting,
            order_by: [{:desc, :id}]
        )
    end
  end

  defp setting_cache_key(name) do
    "site-settings:#{name}"
  end

  def get_setting(name) do
    cache_key = setting_cache_key(name)

    case Cachex.get(:ysc_cache, cache_key) do
      {:ok, nil} ->
        setting_value = get_setting_value_from_db!(name)
        Cachex.put(:ysc_cache, cache_key, setting_value)
        setting_value

      {:ok, value} ->
        value

      _ ->
        get_setting_value_from_db!(name)
    end
  end

  defp get_setting_value_from_db!(name) do
    setting = Repo.get_by!(SiteSetting, name: name)
    setting.value
  end

  def update_setting(name, value) do
    current_setting = Repo.get_by!(SiteSetting, name: name)

    case SiteSetting.site_setting_changeset(current_setting, %{value: value})
         |> Repo.update() do
      {:ok, updated} ->
        # Update both caches
        Cachex.put(:ysc_cache, setting_cache_key(name), value)

        case Cachex.get(:ysc_cache, @settings_cache_key) do
          {:ok, settings} when is_list(settings) ->
            updated_settings =
              Enum.map(settings, fn setting ->
                if setting.name == name, do: updated, else: setting
              end)

            Cachex.put(:ysc_cache, @settings_cache_key, updated_settings)

          _ ->
            :ok
        end

        {:ok, updated}

      error ->
        error
    end
  end

  def settings_grouped_by_scope() do
    settings()
    |> Enum.reduce(%{}, fn setting, acc ->
      current = Map.get(acc, setting.group, [])
      Map.put(acc, setting.group, [setting | current])
    end)
  end

  def setting_scopes() do
    settings()
    |> Enum.map(& &1.group)
    |> Enum.uniq()
  end

  def clear_cache() do
    # Clear the main settings cache
    Cachex.del(:ysc_cache, @settings_cache_key)

    # Clear all individual setting caches by fetching all settings and deleting their cache keys
    # Cachex doesn't support wildcard deletion, so we need to delete each key individually
    all_settings = Repo.all(from s in SiteSetting, select: s.name)

    Enum.each(all_settings, fn name ->
      Cachex.del(:ysc_cache, setting_cache_key(name))
    end)
  end
end
