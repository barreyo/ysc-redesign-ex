defmodule YscWeb.Plugs.SiteSettingsPlugs do
  use YscWeb, :verified_routes

  import Plug.Conn

  alias Ysc.Settings

  def on_mount(:mount_site_settings, _params, _session, socket) do
    {:cont, mount_site_settings(socket)}
  end

  def mount_site_settings(conn, _opts) do
    assign(conn, :site_setting_socials_instagram, Settings.get_setting("instagram"))
    |> assign(:site_setting_socials_facebook, Settings.get_setting("facebook"))
  end

  defp mount_site_settings(socket) do
    Phoenix.Component.assign_new(socket, :site_setting_socials_instagram, fn ->
      Settings.get_setting("instagram")
    end)
    |> Phoenix.Component.assign_new(:site_setting_socials_facebook, fn ->
      Settings.get_setting("facebook")
    end)
  end
end
