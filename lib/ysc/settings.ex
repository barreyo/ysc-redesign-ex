defmodule Ysc.Settings do
  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.SiteSettings.SiteSetting

  def settings() do
    Repo.all(SiteSetting)
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
