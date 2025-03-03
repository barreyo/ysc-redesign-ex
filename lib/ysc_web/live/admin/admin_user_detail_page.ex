defmodule YscWeb.AdminUserDetailsLive do
  use YscWeb, :live_view

  alias Ysc.Accounts

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
      <div class="flex flex-col justify-between py-6">
        <.back navigate={~p"/admin/users"}>Back</.back>

        <h1 class="text-2xl font-semibold leading-8 text-zinc-800 pt-4">
          <%= "#{String.capitalize(@first_name)} #{String.capitalize(@last_name)}" %>
        </h1>

        <div class="w-full py-4">
          <div class="h-24">
            <.user_avatar_image
              email={@selected_user.email}
              user_id={@selected_user.id}
              country={@selected_user.most_connected_country}
              class="w-24 h-24 rounded-full"
            />
          </div>
        </div>

        <div class="pt-4">
          <div class="text-sm font-medium text-center text-zinc-500 border-b border-zinc-200">
            <ul class="flex flex-wrap -mb-px">
              <li class="me-2">
                <.link
                  navigate={~p"/admin/users/#{@user_id}/details"}
                  class={[
                    "inline-block p-4 border-b-2 rounded-t-lg",
                    @live_action == :profile && "text-blue-600 border-blue-600 active",
                    @live_action != :profile &&
                      "hover:text-zinc-600 hover:border-zinc-300 border-transparent"
                  ]}
                >
                  Profile
                </.link>
              </li>
              <li class="me-2">
                <.link
                  navigate={~p"/admin/users/#{@user_id}/details/orders"}
                  class={[
                    "inline-block p-4 border-b-2 rounded-t-lg",
                    @live_action == :orders && "text-blue-600 border-blue-600 active",
                    @live_action != :orders &&
                      "hover:text-zinc-600 hover:border-zinc-300 border-transparent"
                  ]}
                >
                  Orders
                </.link>
              </li>
              <li class="me-2">
                <.link
                  navigate={~p"/admin/users/#{@user_id}/details/bookings"}
                  class={[
                    "inline-block p-4 border-b-2 rounded-t-lg",
                    @live_action == :bookings && "text-blue-600 border-blue-600 active",
                    @live_action != :bookings &&
                      "hover:text-zinc-600 hover:border-zinc-300 border-transparent"
                  ]}
                >
                  Bookings
                </.link>
              </li>
              <li class="me-2">
                <.link
                  navigate={~p"/admin/users/#{@user_id}/details/application"}
                  class={[
                    "inline-block p-4 border-b-2 rounded-t-lg",
                    @live_action == :application && "text-blue-600 border-blue-600 active",
                    @live_action != :application &&
                      "hover:text-zinc-600 hover:border-zinc-300 border-transparent"
                  ]}
                >
                  Application
                </.link>
              </li>
            </ul>
          </div>
        </div>

        <div :if={@live_action == :profile} class="max-w-lg px-2">
          <.simple_form for={@form} phx-change="validate" phx-submit="save">
            <.input field={@form[:email]} label="Email" />
            <.input field={@form[:first_name]} label="First Name" />
            <.input field={@form[:last_name]} label="Last Name" />
            <.input
              type="phone-input"
              label="Phone Number"
              id="phone_number"
              value={@form[:phone_number].value}
              field={@form[:phone_number]}
            />
            <.input
              field={@form[:most_connected_country]}
              label="Most connected Nordic country:"
              type="select"
              options={[Sweden: "SE", Norway: "NO", Finland: "FI", Denmark: "DK", Iceland: "IS"]}
            />
            <.input
              type="select"
              field={@form[:state]}
              options={[
                Active: "active",
                "Pending Approval": "pending_approval",
                Rejected: "rejected",
                Suspended: "suspended",
                Deleted: "deleted"
              ]}
              label="State"
            />
            <.input
              type="select"
              field={@form[:role]}
              options={[Member: "member", Admin: "admin"]}
              label="Role"
            />

            <.input
              :if={"#{@role}" == "admin"}
              type="select"
              field={@form[:board_position]}
              options={[
                None: nil,
                President: "president",
                "Vice President": "vice_president",
                Secretary: "secretary",
                Treasurer: "treasurer",
                "Clear Lake Cabin Master": "clear_lake_cabin_master",
                "Tahoe Cabin Master": "tahoe_cabin_master",
                "Event Director": "event_director",
                "Member Outreach & Events": "member_outreach",
                "Membership Director": "membership_director"
              ]}
              label="Board Position"
            />

            <div class="flex flex-row justify-end w-full pt-8">
              <button class="phx-submit-loading:opacity-75 rounded bg-green-700 hover:bg-green-800 py-2 px-3 transition duration-200 ease-in-out disabled:cursor-not-allowed disabled:opacity-80 text-sm font-semibold leading-6 text-zinc-100 active:text-zinc-100/80">
                <.icon name="hero-check" class="w-5 h-5 mb-0.5 me-1" /> Save changes
              </button>
            </div>
          </.simple_form>
        </div>

        <div :if={@live_action == :orders} class="max-w-lg py-8 px-2">
          <p class="text-sm text-zinc-800">No orders (yet!)</p>
        </div>

        <div :if={@live_action == :bookings} class="max-w-lg py-8 px-2">
          <p class="text-sm text-zinc-800">No bookings (yet!)</p>
        </div>

        <div :if={@live_action == :application} class="max-w-lg py-8 px-2">
          <div :if={@selected_user_application == nil}>
            <p class="text-sm text-zinc-800">No application found</p>
          </div>

          <div :if={@selected_user_application != nil}>
            <p class="leading-6 text-sm text-zinc-800 mb-4 font-semibold">
              Submitted:
              <.badge>
                <%= "#{Timex.format!(Timex.Timezone.convert(@selected_user_application.completed, "America/Los_Angeles"), "{YYYY}-{0M}-{0D}")} (#{Timex.from_now(@selected_user_application.completed)})" %>
              </.badge>
            </p>

            <h3 class="leading-6 text-zinc-800 font-semibold mb-2">Applicant Details</h3>
            <ul class="leading-6 text-zinc-800 text-sm pb-6">
              <li><span class="font-semibold">Email:</span> <%= @selected_user.email %></li>
              <li>
                <span class="font-semibold">Name:</span> <%= "#{@selected_user.first_name} #{@selected_user.last_name}" %>
              </li>
              <li>
                <span class="font-semibold">Birth date:</span> <%= @selected_user_application.birth_date %>
              </li>

              <li :if={length(@selected_user.family_members) > 0}>
                <p class="font-semibold">Family members:</p>
                <ul class="space-y-1 text-zinc-800 list-disc list-inside">
                  <li :for={family_member <- @selected_user.family_members}>
                    <span class="text-xs font-medium me-2 px-2.5 py-1 rounded text-left bg-blue-100 text-blue-800">
                      <%= String.capitalize("#{family_member.type}") %>
                    </span>
                    <%= "#{family_member.first_name} #{family_member.last_name} (#{family_member.birth_date})" %>
                  </li>
                </ul>
              </li>
            </ul>

            <h3 class="leading-6 text-zinc-800 font-semibold mb-2">Application Answers</h3>
            <ul class="leading-6 text-sm text-zinc-800 pb-6">
              <li>
                <span class="font-semibold">Membership type:</span> <%= @selected_user_application.membership_type %>
              </li>

              <li class="pt-2">
                <p class="font-semibold">Eligibility:</p>
                <ul class="space-y-1 text-zinc-800 list-disc list-inside">
                  <li :for={reason <- @selected_user_application.membership_eligibility}>
                    <%= Map.get(Ysc.Accounts.SignupApplication.eligibility_lookup(), reason) %>
                  </li>
                </ul>
              </li>
              <li class="pt-2">
                <span class="font-semibold">Occupation:</span> <%= @selected_user_application.occupation %>
              </li>
              <li class="pt-2">
                <span class="font-semibold">Place of birth:</span> <%= @selected_user_application.place_of_birth %>
              </li>
              <li class="pt-2">
                <span class="font-semibold">Citizenship:</span> <%= @selected_user_application.citizenship %>
              </li>
              <li class="pt-2">
                <span class="font-semibold">Most connected Nordic country:</span> <%= @selected_user_application.most_connected_nordic_country %>
              </li>

              <li class="pt-2">
                <span class="font-semibold">Link to Scandinavia:</span>
                <input
                  type="textarea"
                  class="mt-2 block w-full rounded text-zinc-900 sm:text-sm sm:leading-6 bg-zinc-100 px-2 py-3"
                  value={@selected_user_application.link_to_scandinavia}
                  disabled={true}
                />
              </li>
              <li class="pt-2">
                <span class="font-semibold">Lived in Scandinavia:</span>
                <input
                  type="textarea"
                  class="mt-2 block w-full rounded text-zinc-900 sm:text-sm sm:leading-6 bg-zinc-100 px-2 py-3"
                  value={@selected_user_application.lived_in_scandinavia}
                  disabled={true}
                />
              </li>
              <li class="pt-2">
                <span class="font-semibold">Spoken languages:</span>
                <input
                  type="textarea"
                  class="mt-2 block w-full rounded text-zinc-900 sm:text-sm sm:leading-6 bg-zinc-100 px-2 py-3"
                  value={@selected_user_application.spoken_languages}
                  disabled={true}
                />
              </li>
            </ul>
          </div>
        </div>
      </div>
    </.side_menu>
    """
  end

  def mount(%{"id" => id} = _params, _session, socket) do
    current_user = socket.assigns[:current_user]

    selected_user = Accounts.get_user!(id, [:family_members])
    application = Accounts.get_signup_application_from_user_id!(id, current_user, [:reviewed_by])
    user_changeset = Accounts.User.update_user_changeset(selected_user, %{})

    {:ok,
     socket
     |> assign(:user_id, id)
     |> assign(:first_name, selected_user.first_name)
     |> assign(:last_name, selected_user.last_name)
     |> assign(:role, selected_user.role)
     |> assign(:page_title, "Users")
     |> assign(:active_page, :members)
     |> assign(:selected_user, selected_user)
     |> assign(:selected_user_application, application)
     |> assign(form: to_form(user_changeset, as: "user"))}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    current_user = socket.assigns[:current_user]
    assigned = socket.assigns[:selected_user]

    case Accounts.update_user(assigned, user_params, current_user) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> put_flash(:info, "User updated")
         |> redirect(to: ~p"/admin/users/#{updated_user.id}/details")}

      _ ->
        {:noreply, socket |> put_flash(:error, "Something went wrong")}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    assigned = socket.assigns[:selected_user]
    form_data = Accounts.change_user_registration(assigned, user_params)

    {:noreply,
     assign_form(socket, form_data)
     |> assign(:first_name, user_params["first_name"])
     |> assign(:last_name, user_params["last_name"])
     |> assign(:role, user_params["role"])}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end
end
