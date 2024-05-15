defmodule Ysc.Settings do
  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.SiteSettings.SiteSetting

  def settings() do
    Repo.all(SiteSetting)
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

    Cachex.put(:ysc_cache, setting_cache_key(name), value)

    SiteSetting.site_setting_changeset(current_setting, %{
      value: value
    })
    |> Repo.update()
  end

  def settings_grouped_by_scope() do
    settings()
    |> Enum.reduce(%{}, fn setting, acc ->
      current = Map.get(acc, setting.group, [])
      Map.put(acc, setting.group, [setting | current])
    end)
  end

  def setting_scopes() do
    from(s in SiteSetting,
      distinct: s.group,
      select: %{
        "group" => s.group
      }
    )
    |> Repo.all()
    |> Enum.map(fn entry -> Map.get(entry, "group") end)
  end
end
