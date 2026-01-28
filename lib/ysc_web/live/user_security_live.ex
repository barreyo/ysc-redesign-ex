defmodule YscWeb.UserSecurityLive do
  use YscWeb, :live_view

  alias Ysc.Accounts
  alias Ysc.Accounts.UserNotifier
  alias Ysc.Repo

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    current_membership = socket.assigns.current_membership
    active_plan = YscWeb.UserAuth.get_membership_plan_type(current_membership)

    # Initialize password form
    password_changeset = Accounts.change_user_password(user)

    # Initialize with empty passkeys list and loading state
    socket =
      socket
      |> assign(:page_title, "Security Settings")
      |> assign(:user, user)
      |> assign(:current_password, nil)
      |> assign(:current_email, user.email)
      |> assign(:trigger_submit, false)
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:passkeys, [])
      |> assign(:passkeys_loading, true)
      |> assign(:passkeys_loaded, false)
      |> assign(:active_plan_type, active_plan)

    # Load passkeys asynchronously only if connected
    socket =
      if connected?(socket) do
        start_async(socket, :load_passkeys, fn ->
          Accounts.get_user_passkeys(user)
        end)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_async(:load_passkeys, {:ok, passkeys}, socket) do
    {:noreply,
     socket
     |> assign(:passkeys, passkeys)
     |> assign(:passkeys_loading, false)
     |> assign(:passkeys_loaded, true)}
  end

  def handle_async(:load_passkeys, {:exit, reason}, socket) do
    require Logger
    Logger.error("Failed to load passkeys async: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:passkeys_loading, false)
     |> assign(:passkeys_loaded, true)}
  end

  @impl true
  def handle_event("validate_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    password_form =
      socket.assigns.current_user
      |> Accounts.change_user_password(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form, current_password: password)}
  end

  @impl true
  def handle_event("update_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.update_user_password(user, password, user_params) do
      {:ok, user} ->
        UserNotifier.deliver_password_changed_notification(user)

        password_form =
          user
          |> Accounts.change_user_password(user_params)
          |> to_form()

        {:noreply, assign(socket, trigger_submit: true, password_form: password_form)}

      {:error, changeset} ->
        {:noreply, assign(socket, password_form: to_form(changeset))}
    end
  end

  @impl true
  def handle_event("delete_passkey", %{"passkey_id" => id}, socket) do
    user = socket.assigns.current_user

    # Get passkey and verify it belongs to current user
    case Repo.get(Ysc.Accounts.UserPasskey, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Passkey not found.")}

      passkey ->
        if passkey.user_id == user.id do
          case Accounts.delete_user_passkey(passkey) do
            {:ok, _} ->
              # Remove deleted passkey from assigns
              updated_passkeys = Enum.reject(socket.assigns.passkeys, &(&1.id == id))

              {:noreply,
               socket
               |> assign(:passkeys, updated_passkeys)
               |> put_flash(:info, "Passkey deleted successfully.")}

            {:error, _changeset} ->
              {:noreply, put_flash(socket, :error, "Failed to delete passkey. Please try again.")}
          end
        else
          {:noreply, put_flash(socket, :error, "You are not authorized to delete this passkey.")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-screen-xl px-4 mx-auto py-8 lg:py-10">
      <div class="md:flex md:flex-row md:flex-auto md:grow container mx-auto">
        <ul class="flex-column space-y space-y-4 md:pr-10 text-sm font-medium text-zinc-600 md:me-4 mb-4 md:mb-0">
          <li>
            <h2 class="text-zinc-800 text-2xl font-semibold leading-8 mb-10">Account</h2>
          </li>
          <li>
            <.link
              navigate={~p"/users/settings"}
              class={[
                "inline-flex items-center px-4 py-3 rounded w-full",
                "hover:bg-zinc-100 hover:text-zinc-900"
              ]}
            >
              <.icon name="hero-user" class="w-5 h-5 me-2" /> Profile
            </.link>
          </li>
          <li>
            <.link
              navigate={~p"/users/membership"}
              class={[
                "inline-flex items-center px-4 py-3 rounded w-full",
                "hover:bg-zinc-100 hover:text-zinc-900"
              ]}
            >
              <.icon name="hero-heart" class="w-5 h-5 me-2" /> Membership
            </.link>
          </li>
          <li>
            <.link
              navigate={~p"/users/payments"}
              class={[
                "inline-flex items-center px-4 py-3 rounded w-full",
                "hover:bg-zinc-100 hover:text-zinc-900"
              ]}
            >
              <.icon name="hero-wallet" class="w-5 h-5 me-2" /> Payments
            </.link>
          </li>
          <%= if @current_user && (Accounts.primary_user?(@current_user) || Accounts.sub_account?(@current_user)) && (@active_plan_type == :family || @active_plan_type == :lifetime) do %>
            <li>
              <.link
                navigate={~p"/users/settings/family"}
                class={[
                  "inline-flex items-center px-4 py-3 rounded w-full",
                  "hover:bg-zinc-100 hover:text-zinc-900"
                ]}
              >
                <.icon name="hero-user-group" class="w-5 h-5 me-2" /> Family
              </.link>
            </li>
          <% end %>
          <li>
            <.link
              navigate={~p"/users/settings/security"}
              class={[
                "inline-flex items-center px-4 py-3 rounded w-full",
                "bg-blue-600 active text-zinc-100"
              ]}
            >
              <.icon name="hero-shield-check" class="w-5 h-5 me-2" /> Security
            </.link>
          </li>
          <li>
            <.link
              navigate={~p"/users/notifications"}
              class={[
                "inline-flex items-center px-4 py-3 rounded w-full",
                "hover:bg-zinc-100 hover:text-zinc-900"
              ]}
            >
              <.icon name="hero-bell-alert" class="w-5 h-5 me-2" /> Notifications
            </.link>
          </li>
        </ul>

        <div class="text-medium px-2 text-zinc-500 rounded w-full md:border-l md:border-1 md:border-zinc-100 md:pl-16">
          <div class="space-y-8">
            <!-- Passkeys Section -->
            <div class="rounded border border-zinc-100 py-4 px-4 space-y-4">
              <h2 class="text-zinc-900 font-bold text-xl">Passkeys</h2>

              <div :if={@passkeys_loading} class="flex items-center justify-center py-8">
                <div class="animate-spin rounded-full h-6 w-6 border-b-2 border-blue-600"></div>
                <span class="ml-3 text-zinc-600 text-sm">Loading passkeys...</span>
              </div>

              <div :if={@passkeys_loaded && @passkeys == []} class="text-center py-8">
                <p class="text-zinc-600 text-sm mb-4">You don't have any passkeys yet.</p>
                <.link
                  navigate={~p"/users/settings/passkeys/new"}
                  class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700"
                >
                  <.icon name="hero-plus" class="w-5 h-5 me-2" /> Add Passkey
                </.link>
              </div>

              <div :if={@passkeys_loaded && @passkeys != []} class="space-y-4">
                <.link
                  navigate={~p"/users/settings/passkeys/new"}
                  class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 mb-4"
                >
                  <.icon name="hero-plus" class="w-5 h-5 me-2" /> Add Passkey
                </.link>

                <div class="space-y-3">
                  <div
                    :for={passkey <- @passkeys}
                    class="flex items-center justify-between p-4 border border-zinc-200 rounded-lg"
                  >
                    <div class="flex-1">
                      <div class="flex items-center gap-2 mb-1">
                        <.icon name="hero-key" class="w-5 h-5 text-zinc-600" />
                        <p class="text-zinc-900 font-medium">
                          <%= format_passkey_name(passkey) %>
                        </p>
                      </div>
                      <div class="text-sm text-zinc-600 space-y-1">
                        <p>
                          Created: <%= Calendar.strftime(passkey.inserted_at, "%B %d, %Y") %>
                        </p>
                        <p>
                          Last used:
                          <%= if passkey.last_used_at do %>
                            <%= Calendar.strftime(passkey.last_used_at, "%B %d, %Y") %>
                          <% else %>
                            Never
                          <% end %>
                        </p>
                      </div>
                    </div>
                    <div>
                      <.button
                        phx-click="delete_passkey"
                        phx-value-passkey_id={passkey.id}
                        phx-confirm={"Are you sure you want to delete the passkey \"#{format_passkey_name(passkey)}\"? This action cannot be undone."}
                        phx-disable-with="Deleting..."
                        variant="danger"
                        class="ml-4"
                      >
                        <.icon name="hero-trash" class="w-4 h-4 me-1" /> Delete
                      </.button>
                    </div>
                  </div>
                </div>
              </div>
            </div>
            <!-- Password Change Section -->
            <div class="rounded border border-zinc-100 py-4 px-4 space-y-4">
              <h2 class="text-zinc-900 font-bold text-xl">Change Password</h2>

              <.simple_form
                for={@password_form}
                id="password_form"
                action={~p"/users/log-in?_action=password_updated"}
                method="post"
                phx-change="validate_password"
                phx-submit="update_password"
                phx-trigger-action={@trigger_submit}
              >
                <.input
                  field={@password_form[:email]}
                  type="hidden"
                  id="hidden_user_email"
                  value={@current_email}
                />
                <.input
                  field={@password_form[:password]}
                  type="password-toggle"
                  label="New password"
                  required
                />
                <.input
                  field={@password_form[:password_confirmation]}
                  type="password-toggle"
                  label="Confirm new password"
                />
                <.input
                  field={@password_form[:current_password]}
                  name="current_password"
                  type="password-toggle"
                  label="Current password"
                  id="current_password_for_password"
                  value={@current_password}
                  required
                />
                <:actions>
                  <.button phx-disable-with="Changing...">Change Password</.button>
                </:actions>
              </.simple_form>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp format_passkey_name(passkey) do
    if passkey.nickname && passkey.nickname != "" do
      passkey.nickname
    else
      # Fallback for passkeys created before nickname detection was implemented
      "Device (created #{Calendar.strftime(passkey.inserted_at, "%b %Y")})"
    end
  end
end
