defmodule YscWeb.AdminUsersLive do
  use YscWeb, :live_view

  alias Ysc.Accounts

  def render(assigns) do
    ~H"""
    <.side_menu active_page={@active_page}>
      <.modal
        :if={@live_action == :edit}
        id="edit-user-modal"
        on_cancel={JS.navigate(~p"/admin/users?#{@params}")}
        show
      >
        <h2 class="text-2xl font-semibold leading-8 text-zinc-800 mb-4">
          Edit User
        </h2>

        <div>
          <img
            class="w-20 h-20 rounded-full"
            src="https://www.routesnorth.com/wp-content/uploads/2023/08/strong-viking.jpeg"
            alt="Default avatar"
          />
        </div>
      </.modal>

      <.modal
        :if={@live_action == :review}
        id="review-user-modal"
        on_cancel={JS.navigate(~p"/admin/users?#{@params}")}
        show
      >
        <h2 class="text-2xl font-semibold leading-8 text-zinc-800 mb-4">
          Review Application
        </h2>

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
            <ul class="space-y-1 text-gray-800 list-disc list-inside">
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
            <ul class="space-y-1 text-gray-800 list-disc list-inside">
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

        <div class="flex flex-row justify-between w-full pt-8">
          <button
            class="phx-submit-loading:opacity-75 rounded bg-red-700 hover:bg-red-800 py-2 px-3 transition duration-200 ease-in-out disabled:cursor-not-allowed disabled:opacity-80 text-sm font-semibold leading-6 text-zinc-100 active:text-zinc-100/80"
            data-confirm="You are about to reject this application. Are you sure?"
          >
            <.icon name="hero-no-symbol" class="w-5 h-5 mb-0.5 me-1" /> Reject
          </button>
          <button class="phx-submit-loading:opacity-75 rounded bg-green-700 hover:bg-green-800 py-2 px-3 transition duration-200 ease-in-out disabled:cursor-not-allowed disabled:opacity-80 text-sm font-semibold leading-6 text-zinc-100 active:text-zinc-100/80">
            <.icon name="hero-check" class="w-5 h-5 mb-0.5 me-1" /> Approve
          </button>
        </div>
      </.modal>

      <div class="flex justify-between py-6">
        <h1 class="text-2xl font-semibold leading-8 text-zinc-800">
          Users
        </h1>

        <.dropdown
          id="export-users-button"
          right={true}
          class="bg-blue-700 hover:bg-blue-800 text-sm font-semibold leading-6 text-zinc-100 active:text-zinc-100/80"
        >
          <:button_block>
            <.tooltip tooltip_text="Export to CSV">
              <.icon name="hero-document-arrow-down" class="w-5 h-5 me-1 mb-1" />
              <span>Export</span>
            </.tooltip>
          </:button_block>
          <div class="w-full px-4 py-3">
            <h3 class="leading-8 font-semibold text-zinc-800 mb-2">Include Fields</h3>
            <form phx-submit="export-csv" class="flex flex-col gap-y-2 justify-between">
              <%= for attr <- ~w(id email first_name last_name phone_number state)a do %>
                <.input
                  field={@form[attr]}
                  label={export_field_to_label(attr)}
                  type="checkbox"
                  checked={true}
                />
              <% end %>

              <div class="border-t border-zinc-100 py-2">
                <.input
                  field={@form[:only_subscribers]}
                  label="Only users with active memberships"
                  type="checkbox"
                  checked={false}
                />
              </div>
              <.button
                type="submit"
                disabled={!(@export_status == :not_exporting || @export_status == :failed)}
              >
                <span :if={@export_status == :not_exporting || @export_status == :failed}>
                  Export CSV
                </span>
                <.spinner :if={@export_status == :in_progress} class="w-6 h-6 mx-auto" />
                <.icon
                  :if={@export_status == :complete}
                  name="hero-check-circle"
                  class="w-6 h-6 flex-none fill-blue-600 text-zinc-200 mx-auto"
                />
              </.button>

              <.progress_bar :if={@export_status == :in_progress} progress={@export_progress} />

              <p
                :if={@export_status == :failed}
                class="flex gap-1 mt-1 text-sm leading-6 text-rose-600"
              >
                <.icon name="hero-exclamation-circle-mini" class="mt-0.5 w-5 h-5 flex-none" />
                <%= @export_error %>
              </p>

              <a
                :if={@export_status == :complete}
                class="flex gap-1 mt-1 text-sm leading-6"
                href={@file_export_path}
                target="_blank"
              >
                <.icon name="hero-document-check" class="mt-0.5 w-5 h-5 flex-none text-green-600" />
                <span href={@file_export_path} target="_blank" class="text-blue-800 hover:underline">
                  Download file
                </span>
              </a>
            </form>
          </div>
        </.dropdown>
      </div>

      <div class="w-full pt-4">
        <div>
          <form action="" novalidate="" role="search" phx-change="change" class="relative">
            <div class="absolute inset-y-0 rtl:inset-r-0 start-0 flex items-center ps-3 pointer-events-none">
              <.icon name="hero-magnifying-glass" class="w-5 h-5 text-gray-500" />
            </div>
            <input
              id="user-search"
              type="search"
              name="search[query]"
              autocomplete="off"
              autocorrect="off"
              autocapitalize="off"
              enterkeyhint="search"
              spellcheck="false"
              placeholder="Search by name, email or phone number"
              value={@params["search"]}
              tabindex="0"
              phx-debounce={100}
              class="block pt-3 pb-3 ps-10 text-sm text-zinc-800 border border-zinc-200 rounded w-full bg-zinc-50 focus:ring-blue-500 focus:border-blue-500"
            />
          </form>
        </div>
        <div class="py-6 w-full">
          <div id="admin-user-filters" class="pb-4 flex">
            <.dropdown id="filter-state-dropdown" class="group hover:bg-zinc-100">
              <:button_block>
                <.icon
                  name="hero-funnel"
                  class="mr-1 text-zinc-600 w-5 h-5 group-hover:text-zinc-800"
                /> Filters
              </:button_block>

              <div class="w-full px-4 py-3">
                <.filter_form
                  fields={[
                    state: [
                      label: "State",
                      type: "checkgroup",
                      multiple: true,
                      op: :in,
                      options: [
                        {"Active", :active},
                        {"Pending Approval", :pending_approval},
                        {"Suspended", :suspended},
                        {"Rejected", :rejected},
                        {"Deleted", :deleted}
                      ]
                    ],
                    role: [
                      label: "Role",
                      type: "checkgroup",
                      multiple: true,
                      op: :in,
                      options: [
                        {"Member", :member},
                        {"Admin", :admin}
                      ]
                    ]
                  ]}
                  meta={@meta}
                  id="user-filter-form"
                />
              </div>

              <div class="px-4 py-4">
                <button
                  class="rounded bg-red-700 hover:bg-red-800 py-2 px-3 transition duration-200 ease-in-out text-sm font-semibold leading-6 text-zinc-100 active:text-zinc-100/80 w-full"
                  phx-click={JS.navigate(~p"/admin/users")}
                >
                  <.icon name="hero-x-circle" class="w-5 h-5" /> Clear filters
                </button>
              </div>
            </.dropdown>
          </div>

          <Flop.Phoenix.table
            id="admin_users_list"
            items={@streams.users}
            meta={@meta}
            path={~p"/admin/users"}
          >
            <:col :let={{_, user}} label="Name" field={:first_name}>
              <div class="flex items-center text-gray-900 whitespace-nowrap">
                <img
                  class="w-10 h-10 rounded-full"
                  src="https://www.routesnorth.com/wp-content/uploads/2023/08/strong-viking.jpeg"
                  alt="Viking dude"
                />
                <div class="ps-3">
                  <div class="text-sm font-semibold"><%= user_full_name(user) %></div>
                  <div class="font-normal text-zinc-500"><%= user.email %></div>
                </div>
              </div>
            </:col>
            <:col :let={{_, user}} label="Phone" field={:phone_number}>
              <%= format_phone_number(user.phone_number) %>
            </:col>
            <:col :let={{_, user}} label="State" field={:state} thead_th_attrs={[class: "dance"]}>
              <.badge type={user_state_to_badge_type(user.state)}>
                <%= user_state_to_readable(user.state) %>
              </.badge>
            </:col>
            <:col :let={{_, user}} label="Role" field={:role}>
              <%= String.capitalize("#{user.role}") %>
            </:col>
            <:action :let={{_, user}} label="Action">
              <button
                :if={user.state == :pending_approval}
                phx-click={JS.navigate(~p"/admin/users/#{user.id}/review?#{@params}")}
                class="text-blue-600 font-semibold hover:underline cursor-pointer"
              >
                Review
              </button>
              <button
                :if={user.state != :pending_approval}
                phx-click={JS.navigate(~p"/admin/users/#{user.id}?#{@params}")}
                class="text-blue-600 font-semibold hover:underline cursor-pointer"
              >
                Edit
              </button>
            </:action>
          </Flop.Phoenix.table>

          <div :if={@empty} class="py-16">
            <.empty_viking_state
              title="No results found"
              suggestion="Try adjusting your search term and filters."
            />
          </div>

          <Flop.Phoenix.pagination
            meta={@meta}
            path={~p"/admin/users"}
            opts={[
              wrapper_attrs: [class: "flex items-center justify-center py-10 h-10 text-base"],
              pagination_list_attrs: [
                class: [
                  "flex gap-0 order-2 justify-center items-center"
                ]
              ],
              previous_link_attrs: [
                class:
                  "order-1 flex justify-center items-center px-3 py-3 text-sm font-semibold text-zinc-500 hover:text-zinc-800 rounded hover:bg-zinc-100"
              ],
              next_link_attrs: [
                class:
                  "order-3 flex justify-center items-center px-3 py-3 text-sm font-semibold text-zinc-500 hover:text-zinc-800 rounded hover:bg-zinc-100"
              ],
              page_links: {:ellipsis, 5}
            ]}
          />
        </div>
      </div>
    </.side_menu>
    """
  end

  def mount(%{"id" => id} = params, _session, socket) do
    selected_user = Accounts.get_user!(id, [:family_members])
    application = Accounts.get_signup_application_from_user_id!(id)

    {:ok,
     socket
     |> assign(:active_page, :members)
     |> assign(:selected_user, selected_user)
     |> assign(:selected_user_application, application)
     |> assign(:empty, false)
     |> assign(:page_title, "Users")
     |> assign(:params, params)
     |> assign(:export_status, :not_exporting)
     |> assign(:export_progress, 0)
     |> assign(:file_export_path, "")
     |> assign(:export_error, "Something went wrong")
     |> assign(form: to_form(%{}, as: "csv_export"))}
  end

  @spec mount(any(), any(), map()) :: {:ok, map()}
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:active_page, :members)
     |> assign(:empty, false)
     |> assign(:page_title, "Users")
     |> assign(:params, params)
     |> assign(:export_status, :not_exporting)
     |> assign(:export_progress, 0)
     |> assign(:file_export_path, "")
     |> assign(:export_error, "Something went wrong")
     |> assign(form: to_form(%{}, as: "csv_export"))}
  end

  @spec handle_params(
          %{optional(:__struct__) => Flop, optional(atom() | binary()) => any()},
          any(),
          atom() | %{:assigns => nil | maybe_improper_list() | map(), optional(any()) => any()}
        ) :: {:noreply, any()}
  def handle_params(params, _, socket) do
    search = params["search"]

    case Accounts.list_paginated_users(params, search) do
      {:ok, {users, meta}} ->
        {:noreply,
         assign(socket, meta: meta)
         |> assign(:empty, no_results?(users))
         |> assign(:params, params)
         |> stream(:users, users, reset: true)}

      {:error, _meta} ->
        {:noreply, push_navigate(socket, to: ~p"/admin/users")}
    end
  end

  @spec handle_event(
          <<_::48>>,
          map(),
          atom() | %{:assigns => nil | maybe_improper_list() | map(), optional(any()) => any()}
        ) :: {:noreply, any()}
  def handle_event("change", %{"search" => %{"query" => search_query}}, socket) do
    new_params = Map.put(socket.assigns[:params], "search", search_query)
    {:noreply, push_patch(socket, to: ~p"/admin/users?#{new_params}")}
  end

  def handle_event("export-csv", %{"csv_export" => fields}, socket) do
    reduced_fields =
      Enum.reduce(fields, [], fn {field, active}, acc ->
        field = String.to_existing_atom(field)
        if active == "true", do: [field | acc], else: acc
      end)

    reduced_fields = List.delete(reduced_fields, :only_subscribers)

    only_subscribed? =
      Enum.any?(fields, fn {field, active} ->
        field == "only_subscribers" && active == "true"
      end)

    current_user = socket.assigns[:current_user]
    topic = "exporter:#{current_user.id}"
    YscWeb.Endpoint.subscribe(topic)

    # Async exporter
    %{
      channel: topic,
      fields: reduced_fields,
      only_subscribed: only_subscribed?
    }
    |> YscWeb.Workers.UserExporter.new()
    |> Oban.insert()

    {:noreply, socket |> assign(:export_status, :in_progress)}
  end

  def handle_event("update-filter", params, socket) do
    params = Map.delete(params, "_target")

    updated_filters =
      Enum.reduce(params["filters"], %{}, fn {k, v}, red ->
        Map.put(red, k, maybe_update_filter(v))
      end)

    new_params = Map.replace(params, "filters", updated_filters)
    new_params = Map.put(new_params, "search", socket.assigns[:params]["search"])

    {:noreply,
     assign(socket, :params, new_params) |> push_patch(to: ~p"/admin/users?#{new_params}")}
  end

  def handle_event("approve-application", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("deny-application", _params, socket) do
    {:noreply, socket}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{event: "user_export:progress", payload: progress},
        socket
      ) do
    {:noreply, socket |> assign(:export_progress, progress)}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{event: "user_export:complete", payload: path},
        socket
      ) do
    current_user = socket.assigns[:current_user]
    topic = "exporter:#{current_user.id}"
    YscWeb.Endpoint.unsubscribe(topic)

    {:noreply,
     socket
     |> assign(:export_progress, 100)
     |> assign(:export_status, :complete)
     |> assign(:file_export_path, path)}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "user_export:failed", payload: msg}, socket) do
    current_user = socket.assigns[:current_user]
    topic = "exporter:#{current_user.id}"
    YscWeb.Endpoint.unsubscribe(topic)

    {:noreply, socket |> assign(:export_status, :failed) |> assign(:export_error, msg)}
  end

  defp format_phone_number(phone_number) do
    {:ok, parsed} = ExPhoneNumber.parse(phone_number, "")
    ExPhoneNumber.format(parsed, :international)
  end

  defp user_full_name(user) do
    "#{String.capitalize(user.first_name)} #{String.capitalize(user.last_name)}"
  end

  defp maybe_update_filter(%{"value" => [""]} = filter), do: Map.replace(filter, "value", "")
  defp maybe_update_filter(filter), do: filter

  defp no_results?([]), do: true
  defp no_results?(_), do: false

  defp export_field_to_label(:id), do: "User ID"
  defp export_field_to_label(:email), do: "Email"
  defp export_field_to_label(:first_name), do: "First Name"
  defp export_field_to_label(:last_name), do: "Last Name"
  defp export_field_to_label(:phone_number), do: "Phone Number"
  defp export_field_to_label(:state), do: "Account State"
  defp export_field_to_label(field), do: "#{field}"

  # "pending_approval", "rejected", "active", "suspended", "deleted"
  defp user_state_to_badge_type(:active), do: "green"
  defp user_state_to_badge_type(:pending_approval), do: "yellow"
  defp user_state_to_badge_type(:rejected), do: "red"
  defp user_state_to_badge_type(:suspended), do: "red"
  defp user_state_to_badge_type(:deleted), do: "dark"
  defp user_state_to_badge_type(_), do: "default"

  defp user_state_to_readable(:pending_approval), do: "Pending Approval"
  defp user_state_to_readable(state), do: String.capitalize("#{state}")
end
