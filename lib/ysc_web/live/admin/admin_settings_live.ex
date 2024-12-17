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
        <div id="admin-settings" class="max-w-screen-md">
          <.form for={@form} id="admin-settings-form" phx-submit="update-settings">
            <div :for={scope <- @scopes}>
              <h2 class="text-lg leading-8 font-semibold text-zinc-800">
                <%= String.capitalize(scope) %>
              </h2>
              <div>
                <ul>
                  <li :for={entry <- Map.get(@grouped_settings, scope)} class="py-2">
                    <label class="leading-6 text-zinc-800 font-semibold" for={entry.id}>
                      <%= String.capitalize(entry.name) %>:
                    </label>
                    <input
                      id={entry.id}
                      type="text"
                      class="mt-2 block w-full rounded text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6 border-zinc-300 focus:border-zinc-400"
                      name={"settings[#{entry.name}][value]"}
                      value={entry.value}
                    />
                    <input name={"settings[#{entry.name}][name]"} type="hidden" value={entry.name} />
                    <input name={"settings[#{entry.name}][group]"} type="hidden" value={entry.group} />
                  </li>
                </ul>
              </div>
            </div>
            <button
              class="mt-4 phx-submit-loading:opacity-75 rounded bg-blue-700 hover:bg-blue-800 py-2 px-6 transition duration-200 ease-in-out disabled:cursor-not-allowed disabled:opacity-80 text-sm font-semibold leading-6 text-zinc-100 active:text-zinc-100/80"
              phx-disable-with="Saving..."
              type="submit"
            >
              Save
            </button>
          </.form>
        </div>

        <div class="w-full py-4">
          <h2 class="text-lg leading-8 font-semibold text-zinc-800 mb-3">Misc</h2>
          <.link
            class="rounded px-4 py-3 bg-blue-700 hover:bg-blue-800 transition duration-200 ease-in-out text-sm font-semibold leading-6 text-zinc-100"
            navigate={~p"/admin/dashboard"}
          >
            <.icon name="hero-arrow-top-right-on-square" class=" text-zinc-100 w-4 h-4 -mt-1 mr-2" />
            System Dashboard
          </.link>
        </div>
      </div>
    </.side_menu>
    """
  end

  def mount(_params, _session, socket) do
    scopes = Settings.setting_scopes()
    all_settings = Settings.settings_grouped_by_scope()

    form = to_form(all_settings, as: "settings")

    {:ok,
     socket
     |> assign(:page_title, "Admin Settings")
     |> assign(:active_page, :admin_settings)
     |> assign(:grouped_settings, all_settings)
     |> assign(:scopes, scopes)
     |> assign(form: form), temporary_assigns: [scopes: [], grouped_settings: %{}, form: nil]}
  end

  def handle_event("update-settings", %{"settings" => settings}, socket) do
    for {k, v} <- settings do
      Settings.update_setting(k, Map.get(v, "value"))
    end

    {:noreply,
     socket |> put_flash(:info, "Settings Updated") |> redirect(to: ~p"/admin/settings")}
  end
end
