defmodule YscWeb.AdminSettingsLive do
  alias Ysc.Settings
  use YscWeb, :live_view

  def render(assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      email={@current_user.email}
      first_name={@current_user.first_name}
      last_name={@current_user.last_name}
      user_id={@current_user.id}
      most_connected_country={@current_user.most_connected_country}
    >
      <div class="flex justify-between py-6">
        <h1 class="text-2xl font-semibold leading-8 text-zinc-800">
          Settings
        </h1>
      </div>

      <div class="w-full">
        <div id="admin-settings">
          <div :for={scope <- @scopes}>
            <h2 class="text-lg leading-8 font-semibold text-zinc-800">
              <%= String.capitalize(scope) %>
            </h2>
            <div>
              <ul>
                <li :for={entry <- Map.get(@grouped_settings, scope)}>
                  <%= "#{entry.name}: #{entry.value}" %>
                </li>
              </ul>
            </div>
          </div>
        </div>
      </div>
    </.side_menu>
    """
  end

  def mount(_params, _session, socket) do
    scopes = Settings.setting_scopes()
    all_settings = Settings.settings_grouped_by_scope()

    {:ok,
     socket
     |> assign(:page_title, "Admin Settings")
     |> assign(:active_page, :admin_settings)
     |> assign(:grouped_settings, all_settings)
     |> assign(:scopes, scopes), temporary_assigns: [scopes: [], grouped_settings: %{}]}
  end
end
