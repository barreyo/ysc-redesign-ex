defmodule YscWeb.AdminUserDetailsLive do
  use YscWeb, :live_view

  alias Ysc.Accounts
  alias Ysc.Ledgers
  alias Ysc.Repo
  alias Ysc.Subscriptions

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
              <li class="me-2">
                <.link
                  navigate={~p"/admin/users/#{@user_id}/details/membership"}
                  class={[
                    "inline-block p-4 border-b-2 rounded-t-lg",
                    @live_action == :membership && "text-blue-600 border-blue-600 active",
                    @live_action != :membership &&
                      "hover:text-zinc-600 hover:border-zinc-300 border-transparent"
                  ]}
                >
                  Membership
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
              <.button phx-disable-with="Saving..." type="submit">
                <.icon name="hero-check" class="w-5 h-5 mb-0.5 me-1" />Save changes
              </.button>
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
                <%= if @selected_user_application.completed do
                  date_str =
                    @selected_user_application.completed
                    |> DateTime.shift_zone!("America/Los_Angeles")
                    |> Timex.format!("{YYYY}-{0M}-{0D}")

                  "#{date_str} (#{Timex.from_now(@selected_user_application.completed)})"
                else
                  "N/A"
                end %>
              </.badge>
            </p>

            <p
              :if={@selected_user_application.review_outcome != nil}
              class="leading-6 text-sm text-zinc-800 mb-4 font-semibold"
            >
              Review outcome:
              <.badge>
                <%= @selected_user_application.review_outcome %>
              </.badge>
            </p>

            <p
              :if={@selected_user_application.reviewed_by != nil}
              class="leading-6 text-sm text-zinc-800 mb-4"
            >
              <span class="font-semibold">Reviewed by:</span> <%= @selected_user_application.reviewed_by.first_name %> <%= @selected_user_application.reviewed_by.last_name %> (<%= @selected_user_application.reviewed_by.email %>)
            </p>

            <p
              :if={@selected_user_application.reviewed_at != nil}
              class="leading-6 text-sm text-zinc-800 mb-4"
            >
              <span class="font-semibold">Reviewed at:</span>
              <.badge>
                <%= if @selected_user_application.reviewed_at do
                  format_datetime_for_display(@selected_user_application.reviewed_at)
                else
                  "N/A"
                end %>
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

        <div :if={@live_action == :membership} class="max-w-lg py-8 px-2">
          <div class="space-y-6">
            <div
              :if={@has_lifetime_membership}
              class="bg-blue-50 border border-blue-200 rounded-lg p-4"
            >
              <h3 class="text-lg font-semibold text-blue-900 mb-3">Lifetime Membership</h3>
              <div class="space-y-2 text-sm text-blue-800">
                <p>
                  <span class="font-semibold">Status:</span>
                  <.badge class="bg-blue-600 text-white">
                    Active - Never Expires
                  </.badge>
                </p>
                <p>
                  <span class="font-semibold">Awarded on:</span>
                  <%= if @selected_user.lifetime_membership_awarded_at do
                    format_datetime_for_display(@selected_user.lifetime_membership_awarded_at)
                  else
                    "N/A"
                  end %>
                </p>
                <p class="text-xs text-blue-700 pt-2">
                  Lifetime membership provides all Family membership perks and never expires.
                </p>
              </div>
            </div>

            <div
              :if={@active_subscription == nil && !@has_lifetime_membership}
              class="bg-zinc-50 border border-zinc-200 rounded-lg p-4"
            >
              <p class="text-sm text-zinc-800">No active membership subscription found</p>
              <p class="text-xs text-zinc-600 mt-2">You can award lifetime membership below.</p>
            </div>

            <div :if={@active_subscription != nil} class="space-y-6">
              <div>
                <h3 class="text-lg font-semibold text-zinc-800 mb-4">Current Membership</h3>
                <div class="space-y-2 text-sm text-zinc-800">
                  <p>
                    <span class="font-semibold">Plan:</span>
                    <%= get_membership_plan_name(@active_subscription) %>
                  </p>
                  <p>
                    <span class="font-semibold">Status:</span>
                    <.badge>
                      <%= String.capitalize(@active_subscription.stripe_status) %>
                    </.badge>
                  </p>
                  <p>
                    <span class="font-semibold">Current Period Start:</span>
                    <%= if @active_subscription.current_period_start do
                      format_datetime_for_display(@active_subscription.current_period_start)
                    else
                      "N/A"
                    end %>
                  </p>
                  <p>
                    <span class="font-semibold">Current Period End:</span>
                    <%= if @active_subscription.current_period_end do
                      format_datetime_for_display(@active_subscription.current_period_end)
                    else
                      "N/A"
                    end %>
                  </p>
                  <p :if={@active_subscription.ends_at}>
                    <span class="font-semibold">Scheduled Cancellation:</span>
                    <%= format_datetime_for_display(@active_subscription.ends_at) %>
                  </p>
                  <p>
                    <span class="font-semibold">Stripe Subscription ID:</span>
                    <code class="text-xs bg-zinc-100 px-2 py-1 rounded">
                      <%= @active_subscription.stripe_id %>
                    </code>
                  </p>
                </div>
              </div>

              <div class="border-t border-zinc-200 pt-6">
                <h3 class="text-lg font-semibold text-zinc-800 mb-4">Change Membership Type</h3>
                <p class="text-sm text-zinc-600 mb-4">
                  Change the user's membership plan. Upgrades will be charged immediately, downgrades will take effect at the next renewal.
                </p>
                <.simple_form
                  for={@membership_type_form}
                  phx-change="validate_membership_type"
                  phx-submit="update_membership_type"
                >
                  <.input
                    field={@membership_type_form[:membership_type]}
                    type="select"
                    label="New Membership Type"
                    options={get_membership_type_options(@active_subscription)}
                  />
                  <div class="flex flex-row justify-end w-full pt-4">
                    <.button phx-disable-with="Changing..." type="submit">
                      <.icon name="hero-arrows-right-left" class="w-5 h-5 mb-0.5 me-1" />
                      Change Membership Type
                    </.button>
                  </div>
                </.simple_form>
              </div>

              <div class="border-t border-zinc-200 pt-6">
                <h3 class="text-lg font-semibold text-zinc-800 mb-4">Override Membership Length</h3>
                <p class="text-sm text-zinc-600 mb-4">
                  Set a new period end date for this subscription. This will update the billing cycle anchor in Stripe.
                </p>
                <.simple_form
                  for={@membership_form}
                  phx-change="validate_membership"
                  phx-submit="update_membership_period"
                >
                  <.input
                    field={@membership_form[:period_end_date]}
                    type="datetime-local"
                    label="New Period End Date"
                    value={
                      if @membership_form[:period_end_date].value do
                        format_datetime_local(@membership_form[:period_end_date].value)
                      else
                        format_datetime_local(@active_subscription.current_period_end)
                      end
                    }
                  />
                  <div class="flex flex-row justify-end w-full pt-4">
                    <.button phx-disable-with="Updating..." type="submit">
                      <.icon name="hero-check" class="w-5 h-5 mb-0.5 me-1" /> Update Period End
                    </.button>
                  </div>
                </.simple_form>
              </div>

              <div class="border-t border-zinc-200 pt-6">
                <h3 class="text-lg font-semibold text-zinc-800 mb-4">Payment History</h3>

                <div :if={length(@subscription_payments) == 0} class="text-sm text-zinc-600">
                  <p>No payment history found for this subscription.</p>
                </div>

                <div :if={length(@subscription_payments) > 0} class="overflow-x-auto">
                  <table class="min-w-full divide-y divide-zinc-200">
                    <thead class="bg-zinc-50">
                      <tr>
                        <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                          Date
                        </th>
                        <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                          Amount
                        </th>
                        <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                          Status
                        </th>
                        <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                          Invoice ID
                        </th>
                        <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                          Payment Method
                        </th>
                      </tr>
                    </thead>
                    <tbody class="bg-white divide-y divide-zinc-200">
                      <tr :for={payment <- @subscription_payments} class="hover:bg-zinc-50">
                        <td class="px-4 py-3 whitespace-nowrap text-sm text-zinc-800">
                          <%= if payment.payment_date do
                            format_datetime_for_display(payment.payment_date)
                          else
                            "N/A"
                          end %>
                        </td>
                        <td class="px-4 py-3 whitespace-nowrap text-sm font-medium text-zinc-900">
                          <%= Ysc.MoneyHelper.format_money!(payment.amount) %>
                        </td>
                        <td class="px-4 py-3 whitespace-nowrap">
                          <.badge>
                            <%= String.capitalize("#{payment.status}") %>
                          </.badge>
                        </td>
                        <td class="px-4 py-3 whitespace-nowrap text-sm text-zinc-600">
                          <code class="text-xs bg-zinc-100 px-2 py-1 rounded">
                            <%= if payment.external_payment_id do
                              String.slice(payment.external_payment_id, 0..20) <>
                                if(String.length(payment.external_payment_id) > 20,
                                  do: "...",
                                  else: ""
                                )
                            else
                              "N/A"
                            end %>
                          </code>
                        </td>
                        <td class="px-4 py-3 whitespace-nowrap text-sm text-zinc-600">
                          <%= if payment.payment_method do
                            case payment.payment_method.type do
                              "card" ->
                                if payment.payment_method.last4 do
                                  "Card ending in #{payment.payment_method.last4}"
                                else
                                  "Card"
                                end

                              "us_bank_account" ->
                                if payment.payment_method.last4 do
                                  "Bank ending in #{payment.payment_method.last4}"
                                else
                                  "Bank account"
                                end

                              _ ->
                                "Payment method"
                            end
                          else
                            "N/A"
                          end %>
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </div>
            </div>

            <div class="border-t border-zinc-200 pt-6">
              <h3 class="text-lg font-semibold text-zinc-800 mb-4">Lifetime Membership Management</h3>
              <p class="text-sm text-zinc-600 mb-4">
                Award or revoke lifetime membership. Lifetime members never need to pay and have all Family membership perks.
                <strong>This works regardless of subscription status.</strong>
              </p>
              <.simple_form
                for={@lifetime_form}
                phx-change="validate_lifetime"
                phx-submit="update_lifetime_membership"
              >
                <.input
                  field={@lifetime_form[:has_lifetime]}
                  type="checkbox"
                  label="User has lifetime membership"
                />
                <.input
                  :if={@lifetime_form[:has_lifetime].value}
                  field={@lifetime_form[:awarded_at]}
                  type="datetime-local"
                  label="Awarded Date (can be in the past)"
                  value={
                    if @lifetime_form[:awarded_at].value do
                      format_datetime_local(@lifetime_form[:awarded_at].value)
                    else
                      format_datetime_local(DateTime.utc_now())
                    end
                  }
                />
                <div class="flex flex-row justify-end w-full pt-4">
                  <.button phx-disable-with="Saving..." type="submit">
                    <.icon name="hero-check" class="w-5 h-5 mb-0.5 me-1" /> Save Lifetime Membership
                  </.button>
                </div>
              </.simple_form>
            </div>
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

    # Load active subscription
    active_subscription = Subscriptions.get_active_subscription(selected_user)

    # Preload subscription items if subscription exists
    active_subscription =
      if active_subscription do
        Repo.preload(active_subscription, :subscription_items)
      else
        nil
      end

    # Load subscription payments if subscription exists
    subscription_payments =
      if active_subscription do
        Ledgers.get_payments_for_subscription(active_subscription.id)
      else
        []
      end

    # Check for lifetime membership
    has_lifetime = Accounts.has_lifetime_membership?(selected_user)

    # Create membership form changeset
    membership_changeset =
      %{
        period_end_date: active_subscription && active_subscription.current_period_end
      }
      |> membership_changeset()

    # Create lifetime membership form changeset
    lifetime_changeset =
      %{
        has_lifetime: has_lifetime,
        awarded_at: selected_user.lifetime_membership_awarded_at || DateTime.utc_now()
      }
      |> lifetime_membership_changeset()

    # Create membership type form changeset
    current_membership_type = get_current_membership_type_from_subscription(active_subscription)

    membership_type_changeset =
      %{
        membership_type: current_membership_type
      }
      |> membership_type_changeset()

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
     |> assign(:active_subscription, active_subscription)
     |> assign(:subscription_payments, subscription_payments)
     |> assign(:has_lifetime_membership, has_lifetime)
     |> assign(:membership_form, to_form(membership_changeset, as: "membership"))
     |> assign(:membership_type_form, to_form(membership_type_changeset, as: "membership_type"))
     |> assign(:lifetime_form, to_form(lifetime_changeset, as: "lifetime"))
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

  def handle_event("validate_lifetime", %{"lifetime" => lifetime_params}, socket) do
    changeset = lifetime_params |> lifetime_membership_changeset()

    {:noreply, assign(socket, lifetime_form: to_form(changeset, as: "lifetime"))}
  end

  def handle_event("update_lifetime_membership", %{"lifetime" => lifetime_params}, socket) do
    selected_user = socket.assigns[:selected_user]

    has_lifetime =
      lifetime_params["has_lifetime"] == "true" || lifetime_params["has_lifetime"] == true

    update_params =
      if has_lifetime do
        case parse_datetime(lifetime_params["awarded_at"]) do
          {:ok, awarded_at} ->
            %{lifetime_membership_awarded_at: awarded_at}

          {:error, _} ->
            # Use current time if date parsing fails
            %{lifetime_membership_awarded_at: DateTime.utc_now()}
        end
      else
        %{lifetime_membership_awarded_at: nil}
      end

    case Accounts.update_user(selected_user, update_params, socket.assigns[:current_user]) do
      {:ok, updated_user} ->
        # Reload user to get updated lifetime membership status
        updated_user = Accounts.get_user!(updated_user.id)

        lifetime_changeset =
          %{
            has_lifetime: Accounts.has_lifetime_membership?(updated_user),
            awarded_at: updated_user.lifetime_membership_awarded_at || DateTime.utc_now()
          }
          |> lifetime_membership_changeset()

        {:noreply,
         socket
         |> assign(:selected_user, updated_user)
         |> assign(:has_lifetime_membership, Accounts.has_lifetime_membership?(updated_user))
         |> assign(:lifetime_form, to_form(lifetime_changeset, as: "lifetime"))
         |> put_flash(
           :info,
           if(has_lifetime,
             do: "Lifetime membership awarded",
             else: "Lifetime membership revoked"
           )
         )}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Failed to update lifetime membership: #{inspect(changeset.errors)}"
         )}
    end
  end

  def handle_event("validate_membership", %{"membership" => membership_params}, socket) do
    changeset = membership_params |> membership_changeset()

    {:noreply, assign(socket, membership_form: to_form(changeset, as: "membership"))}
  end

  def handle_event(
        "validate_membership_type",
        %{"membership_type" => membership_type_params},
        socket
      ) do
    changeset = membership_type_params |> membership_type_changeset()

    {:noreply, assign(socket, membership_type_form: to_form(changeset, as: "membership_type"))}
  end

  def handle_event(
        "update_membership_type",
        %{"membership_type" => membership_type_params},
        socket
      ) do
    active_subscription = socket.assigns[:active_subscription]

    if is_nil(active_subscription) do
      {:noreply,
       socket
       |> put_flash(:error, "User does not have an active subscription to change")}
    else
      new_membership_type_str = membership_type_params["membership_type"]

      if is_nil(new_membership_type_str) or new_membership_type_str == "" do
        {:noreply, socket |> put_flash(:error, "Please select a membership type")}
      else
        new_membership_type = String.to_existing_atom(new_membership_type_str)

        # Get membership plans
        membership_plans = Application.get_env(:ysc, :membership_plans, [])

        # Find current and new plans
        current_type = get_current_membership_type_from_subscription(active_subscription)
        current_plan = Enum.find(membership_plans, &(&1.id == current_type))
        new_plan = Enum.find(membership_plans, &(&1.id == new_membership_type))

        cond do
          is_nil(new_plan) ->
            {:noreply, socket |> put_flash(:error, "Invalid membership type selected")}

          current_type == new_membership_type ->
            {:noreply, socket |> put_flash(:info, "User is already on that membership plan")}

          is_nil(current_plan) ->
            {:noreply, socket |> put_flash(:error, "Could not determine current membership plan")}

          true ->
            new_price_id = new_plan.stripe_price_id
            direction = if new_plan.amount > current_plan.amount, do: :upgrade, else: :downgrade

            case Subscriptions.change_membership_plan(
                   active_subscription,
                   new_price_id,
                   direction
                 ) do
              {:ok, updated_subscription} ->
                # Reload subscription with items
                updated_subscription =
                  updated_subscription
                  |> Repo.preload(:subscription_items)

                # Update membership type form
                membership_type_changeset =
                  %{membership_type: new_membership_type}
                  |> membership_type_changeset()

                {:noreply,
                 socket
                 |> assign(:active_subscription, updated_subscription)
                 |> assign(
                   :membership_type_form,
                   to_form(membership_type_changeset, as: "membership_type")
                 )
                 |> put_flash(
                   :info,
                   "Membership type changed from #{String.capitalize("#{current_type}")} to #{String.capitalize("#{new_membership_type}")}"
                 )}

              {:error, error} ->
                error_message =
                  case error do
                    %{message: msg} -> msg
                    msg when is_binary(msg) -> msg
                    _ -> "Failed to change membership type"
                  end

                {:noreply,
                 socket |> put_flash(:error, "Failed to change membership type: #{error_message}")}
            end
        end
      end
    end
  end

  def handle_event("update_membership_period", %{"membership" => membership_params}, socket) do
    active_subscription = socket.assigns[:active_subscription]

    if active_subscription == nil do
      {:noreply, socket |> put_flash(:error, "No active subscription found")}
    else
      case parse_datetime(membership_params["period_end_date"]) do
        {:ok, new_end_date} ->
          case Subscriptions.update_period_end(active_subscription, new_end_date) do
            {:ok, updated_subscription} ->
              # Reload the subscription with items
              updated_subscription = Repo.preload(updated_subscription, :subscription_items)

              # Reload payments for the subscription
              subscription_payments =
                Ledgers.get_payments_for_subscription(updated_subscription.id)

              membership_changeset =
                %{period_end_date: updated_subscription.current_period_end}
                |> membership_changeset()

              {:noreply,
               socket
               |> assign(:active_subscription, updated_subscription)
               |> assign(:subscription_payments, subscription_payments)
               |> assign(:membership_form, to_form(membership_changeset, as: "membership"))
               |> put_flash(:info, "Membership period updated successfully")}

            {:error, error} ->
              {:noreply,
               socket
               |> put_flash(:error, "Failed to update membership period: #{inspect(error)}")}
          end

        {:error, _reason} ->
          {:noreply, socket |> put_flash(:error, "Invalid date format")}
      end
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end

  defp membership_changeset(params) do
    types = %{period_end_date: :utc_datetime}

    {%{}, types}
    |> Ecto.Changeset.cast(params, [:period_end_date])
    |> Ecto.Changeset.validate_required([:period_end_date])
  end

  defp get_membership_plan_name(subscription) do
    case subscription.subscription_items do
      [item | _] ->
        membership_plans = Application.get_env(:ysc, :membership_plans, [])

        case Enum.find(membership_plans, &(&1.stripe_price_id == item.stripe_price_id)) do
          %{name: name} -> "#{name} Membership"
          _ -> "Unknown Membership"
        end

      _ ->
        "Unknown Membership"
    end
  end

  defp format_datetime_for_display(nil), do: "N/A"

  defp format_datetime_for_display(%DateTime{} = datetime) do
    # Convert UTC datetime to America/Los_Angeles timezone
    datetime
    |> DateTime.shift_zone!("America/Los_Angeles")
    |> Timex.format!("{YYYY}-{0M}-{0D} {h12}:{m} {AM} {Zabbr}")
  end

  defp format_datetime_local(%DateTime{} = datetime) do
    # Convert UTC datetime to America/Los_Angeles for datetime-local input
    # datetime-local inputs expect a naive datetime string in local timezone
    datetime
    |> DateTime.shift_zone!("America/Los_Angeles")
    |> DateTime.to_naive()
    |> NaiveDateTime.truncate(:second)
    |> Calendar.strftime("%Y-%m-%dT%H:%M")
  end

  defp format_datetime_local(nil), do: ""
  defp format_datetime_local(datetime) when is_binary(datetime), do: datetime

  defp parse_datetime(datetime_string) when is_binary(datetime_string) do
    # Parse datetime-local string (assumed to be in America/Los_Angeles timezone)
    # and convert to UTC for storage
    case NaiveDateTime.from_iso8601("#{datetime_string}:00") do
      {:ok, naive_dt} ->
        # Create DateTime in America/Los_Angeles timezone
        local_dt = DateTime.from_naive!(naive_dt, "America/Los_Angeles")
        # Convert to UTC for storage
        {:ok, DateTime.shift_zone!(local_dt, "Etc/UTC")}

      error ->
        error
    end
  end

  defp parse_datetime(_), do: {:error, :invalid_format}

  defp lifetime_membership_changeset(params) do
    types = %{has_lifetime: :boolean, awarded_at: :utc_datetime}

    {%{}, types}
    |> Ecto.Changeset.cast(params, [:has_lifetime, :awarded_at])
  end

  defp membership_type_changeset(params) do
    types = %{membership_type: :string}

    {%{}, types}
    |> Ecto.Changeset.cast(params, [:membership_type])
    |> Ecto.Changeset.validate_required([:membership_type])
  end

  defp get_current_membership_type_from_subscription(nil), do: nil

  defp get_current_membership_type_from_subscription(subscription) do
    case subscription.subscription_items do
      [item | _] ->
        membership_plans = Application.get_env(:ysc, :membership_plans, [])

        case Enum.find(membership_plans, &(&1.stripe_price_id == item.stripe_price_id)) do
          %{id: id} -> id
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp get_membership_type_options(_subscription) do
    membership_plans = Application.get_env(:ysc, :membership_plans, [])

    # Filter out lifetime membership (it's handled separately)
    available_plans = Enum.filter(membership_plans, &(&1.id != :lifetime))

    Enum.map(available_plans, fn plan ->
      label = "#{plan.name} - $#{plan.amount}/year"
      value = Atom.to_string(plan.id)
      {label, value}
    end)
  end
end
