defmodule YscWeb.AdminUserDetailsLive do
  use YscWeb, :live_view

  alias Ysc.Accounts
  alias Ysc.Bookings
  alias Ysc.Ledgers
  alias Ysc.Messages
  alias Ysc.Repo
  alias Ysc.Subscriptions
  alias Ysc.Tickets

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
                  Tickets
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
              <li class="me-2">
                <.link
                  navigate={~p"/admin/users/#{@user_id}/details/notifications"}
                  class={[
                    "inline-block p-4 border-b-2 rounded-t-lg",
                    @live_action == :notifications && "text-blue-600 border-blue-600 active",
                    @live_action != :notifications &&
                      "hover:text-zinc-600 hover:border-zinc-300 border-transparent"
                  ]}
                >
                  Notifications
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

        <div :if={@live_action == :orders} class="max-w-full py-8 px-2">
          <h2 class="text-xl font-semibold text-zinc-800 mb-4">Ticket Orders</h2>
          <div class="w-full">
            <Flop.Phoenix.table
              id="user_ticket_orders_list"
              items={@streams.ticket_orders}
              meta={@ticket_orders_meta}
              path={~p"/admin/users/#{@user_id}/details/orders"}
            >
              <:col :let={{_, order}} label="Order ID" field={:reference_id}>
                <.badge type="default" class="whitespace-nowrap">
                  <span class="font-mono text-xs">
                    <%= order.reference_id %>
                  </span>
                </.badge>
              </:col>
              <:col :let={{_, order}} label="Event" field={:inserted_at}>
                <%= if order.event do %>
                  <div class="text-sm font-semibold text-zinc-800">
                    <%= order.event.title %>
                  </div>
                  <%= if order.event.start_date do %>
                    <div class="text-xs text-zinc-500 mt-0.5">
                      <%= Calendar.strftime(order.event.start_date, "%b %d, %Y") %>
                    </div>
                  <% end %>
                <% else %>
                  <span class="text-zinc-400">—</span>
                <% end %>
              </:col>
              <:col :let={{_, order}} label="Tickets">
                <span class="text-sm text-zinc-600">
                  <%= length(order.tickets || []) %> ticket(s)
                </span>
              </:col>
              <:col :let={{_, order}} label="Amount" field={:total_amount}>
                <span class="text-sm font-medium text-zinc-900">
                  <%= Ysc.MoneyHelper.format_money!(order.total_amount) %>
                </span>
              </:col>
              <:col :let={{_, order}} label="Status" field={:status}>
                <%= case order.status do %>
                  <% :pending -> %>
                    <.badge type="yellow" class="whitespace-nowrap flex-shrink-0">Pending</.badge>
                  <% :completed -> %>
                    <.badge type="green" class="whitespace-nowrap flex-shrink-0">Completed</.badge>
                  <% :cancelled -> %>
                    <.badge type="red" class="whitespace-nowrap flex-shrink-0">Cancelled</.badge>
                  <% :expired -> %>
                    <.badge type="dark" class="whitespace-nowrap flex-shrink-0">Expired</.badge>
                  <% _ -> %>
                    <.badge type="dark" class="whitespace-nowrap flex-shrink-0">—</.badge>
                <% end %>
              </:col>
              <:col :let={{_, order}} label="Order Date" field={:inserted_at}>
                <span class="text-sm text-zinc-600">
                  <%= Calendar.strftime(order.inserted_at, "%b %d, %Y") %>
                </span>
              </:col>
            </Flop.Phoenix.table>

            <Flop.Phoenix.pagination
              :if={@ticket_orders_meta}
              meta={@ticket_orders_meta}
              path={~p"/admin/users/#{@user_id}/details/orders"}
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

        <div :if={@live_action == :bookings} class="max-w-full py-8 px-2">
          <h2 class="text-xl font-semibold text-zinc-800 mb-4">Bookings</h2>
          <div class="w-full">
            <Flop.Phoenix.table
              id="user_bookings_list"
              items={@streams.bookings}
              meta={@bookings_meta}
              path={~p"/admin/users/#{@user_id}/details/bookings"}
            >
              <:col :let={{_, booking}} label="Reference" field={:reference_id}>
                <.badge type="default" class="whitespace-nowrap">
                  <span class="font-mono text-xs flex-shrink-0 whitespace-nowrap">
                    <%= booking.reference_id %>
                  </span>
                </.badge>
              </:col>
              <:col :let={{_, booking}} label="Property" field={:property}>
                <span class="text-sm text-zinc-800">
                  <%= case booking.property do %>
                    <% :tahoe -> %>
                      Lake Tahoe
                    <% :clear_lake -> %>
                      Clear Lake
                    <% _ -> %>
                      —
                  <% end %>
                </span>
              </:col>
              <:col :let={{_, booking}} label="Check-in" field={:checkin_date}>
                <span class="text-sm text-zinc-800">
                  <%= Calendar.strftime(booking.checkin_date, "%b %d, %Y") %>
                </span>
              </:col>
              <:col :let={{_, booking}} label="Check-out" field={:checkout_date}>
                <span class="text-sm text-zinc-800">
                  <%= Calendar.strftime(booking.checkout_date, "%b %d, %Y") %>
                </span>
              </:col>
              <:col :let={{_, booking}} label="Nights">
                <span class="text-sm text-zinc-600">
                  <%= Date.diff(booking.checkout_date, booking.checkin_date) %>
                </span>
              </:col>
              <:col :let={{_, booking}} label="Guests" field={:guests_count}>
                <span class="text-sm text-zinc-600">
                  <%= booking.guests_count %>
                </span>
              </:col>
              <:col :let={{_, booking}} label="Room" field={:booking_mode}>
                <%= if Ecto.assoc_loaded?(booking.rooms) && length(booking.rooms) > 0 do %>
                  <div class="space-y-1">
                    <%= for room <- booking.rooms do %>
                      <div>
                        <div class="text-sm font-medium text-zinc-800">
                          <%= room.name %>
                        </div>
                        <%= if room.room_category do %>
                          <div class="text-xs text-zinc-500 mt-0.5">
                            <%= String.capitalize(to_string(room.room_category.name)) %>
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                <% else %>
                  <.badge type="green" class="whitespace-nowrap flex-shrink-0">Full Buyout</.badge>
                <% end %>
              </:col>
              <:col :let={{_, booking}} label="Status" field={:status}>
                <%= case booking.status do %>
                  <% :draft -> %>
                    <.badge type="dark" class="whitespace-nowrap flex-shrink-0">Draft</.badge>
                  <% :hold -> %>
                    <.badge type="yellow" class="whitespace-nowrap flex-shrink-0">Hold</.badge>
                  <% :complete -> %>
                    <.badge type="green" class="whitespace-nowrap flex-shrink-0">Complete</.badge>
                  <% :refunded -> %>
                    <.badge type="sky" class="whitespace-nowrap flex-shrink-0">Refunded</.badge>
                  <% :canceled -> %>
                    <.badge type="red" class="whitespace-nowrap flex-shrink-0">Canceled</.badge>
                  <% _ -> %>
                    <.badge type="dark" class="whitespace-nowrap flex-shrink-0">—</.badge>
                <% end %>
              </:col>
              <:col :let={{_, booking}} label="Booked" field={:inserted_at}>
                <span class="text-sm text-zinc-600">
                  <%= Calendar.strftime(booking.inserted_at, "%b %d, %Y") %>
                </span>
              </:col>
              <:action :let={{_, booking}} label="Action">
                <.link
                  navigate={~p"/bookings/#{booking.id}"}
                  class="text-blue-600 font-semibold hover:underline cursor-pointer text-sm"
                >
                  View
                </.link>
              </:action>
            </Flop.Phoenix.table>

            <Flop.Phoenix.pagination
              :if={@bookings_meta}
              meta={@bookings_meta}
              path={~p"/admin/users/#{@user_id}/details/bookings"}
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

        <div :if={@live_action == :notifications} class="max-w-full py-8 px-2">
          <div class="flex flex-row flex-nowrap items-stretch gap-0">
            <div
              id="resizable-left-panel"
              phx-update="ignore"
              class={[
                "resizable-left flex-1 flex-auto overflow-auto",
                if(@selected_notification, do: "flex-[0_0_auto]", else: "flex-[1_1_auto]")
              ]}
              style={
                if @selected_notification && @panel_width do
                  "width: calc(100% - #{@panel_width} - 8px); flex-shrink: 0;"
                else
                  nil
                end
              }
            >
              <h2 class="text-xl font-semibold text-zinc-800 mb-4">Notifications</h2>
              <div class="w-full">
                <div :if={length(@notifications) == 0} class="text-sm text-zinc-600 py-8">
                  <p>No notifications found for this user.</p>
                </div>

                <div :if={length(@notifications) > 0} class="overflow-x-auto">
                  <table class="min-w-full divide-y divide-zinc-200">
                    <thead class="bg-zinc-50">
                      <tr>
                        <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                          Sent
                        </th>
                        <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                          Type
                        </th>
                        <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                          Template
                        </th>
                        <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                          Recipient
                        </th>
                      </tr>
                    </thead>
                    <tbody class="bg-white divide-y divide-zinc-200">
                      <tr
                        :for={notification <- @notifications}
                        phx-click="select_notification"
                        phx-value-id={notification.id}
                        class={[
                          "hover:bg-zinc-50 cursor-pointer",
                          @selected_notification && notification.id == @selected_notification.id &&
                            "bg-blue-50"
                        ]}
                      >
                        <td class="px-4 py-3 whitespace-nowrap text-sm text-zinc-800">
                          <%= format_datetime_for_display(notification.inserted_at) %>
                        </td>
                        <td class="px-4 py-3 whitespace-nowrap">
                          <.badge>
                            <%= notification.message_type |> to_string() |> String.capitalize() %>
                          </.badge>
                        </td>
                        <td class="px-4 py-3 whitespace-nowrap text-sm text-zinc-600">
                          <code class="text-xs bg-zinc-100 px-2 py-1 rounded">
                            <%= notification.message_template %>
                          </code>
                        </td>
                        <td class="px-4 py-3 whitespace-nowrap text-sm text-zinc-600">
                          <%= if notification.email do %>
                            <%= notification.email %>
                          <% else %>
                            <%= if notification.phone_number do %>
                              <%= notification.phone_number %>
                            <% else %>
                              <span class="text-zinc-400">—</span>
                            <% end %>
                          <% end %>
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </div>
            </div>

            <div
              :if={@selected_notification}
              id="resizable-right-panel"
              phx-hook="PanelResizer"
              phx-update="ignore"
              data-target=".resizable-right"
              class="resizable-right flex-[0_0_auto] bg-white border-l-4 border-zinc-300 hover:border-blue-500 cursor-ew-resize select-none transition-colors flex flex-row"
              style={
                if @panel_width do
                  "max-height: calc(100vh - 200px); width: #{@panel_width}; flex-shrink: 0;"
                else
                  "max-height: calc(100vh - 200px); width: 40%; flex-shrink: 0;"
                end
              }
            >
              <div
                id="panel-resizer-left-edge"
                class="flex-shrink-0 w-6 cursor-ew-resize z-10 flex items-center justify-center pointer-events-auto"
              >
                <.icon
                  name="hero-arrows-right-left"
                  class="w-4 h-4 text-zinc-400 pointer-events-none"
                />
              </div>
              <div class="flex-1 p-6 overflow-auto">
                <div class="flex justify-between items-start mb-4">
                  <h3 class="text-lg font-semibold text-zinc-800">Message Details</h3>
                  <button
                    phx-click="close_notification_panel"
                    class="text-zinc-400 hover:text-zinc-600"
                    type="button"
                  >
                    <.icon name="hero-x-mark" class="w-5 h-5" />
                  </button>
                </div>

                <div class="space-y-4">
                  <div>
                    <p class="text-xs font-medium text-zinc-500 uppercase tracking-wider mb-1">
                      Sent
                    </p>
                    <p class="text-sm text-zinc-800">
                      <%= format_datetime_for_display(@selected_notification.inserted_at) %>
                    </p>
                  </div>

                  <div>
                    <p class="text-xs font-medium text-zinc-500 uppercase tracking-wider mb-1">
                      Type
                    </p>
                    <p class="text-sm text-zinc-800">
                      <.badge>
                        <%= @selected_notification.message_type |> to_string() |> String.capitalize() %>
                      </.badge>
                    </p>
                  </div>

                  <div>
                    <p class="text-xs font-medium text-zinc-500 uppercase tracking-wider mb-1">
                      Template
                    </p>
                    <p class="text-sm text-zinc-800">
                      <code class="text-xs bg-zinc-100 px-2 py-1 rounded">
                        <%= @selected_notification.message_template %>
                      </code>
                    </p>
                  </div>

                  <div>
                    <p class="text-xs font-medium text-zinc-500 uppercase tracking-wider mb-1">
                      Recipient
                    </p>
                    <p class="text-sm text-zinc-800">
                      <%= if @selected_notification.email do %>
                        <%= @selected_notification.email %>
                      <% else %>
                        <%= if @selected_notification.phone_number do %>
                          <%= @selected_notification.phone_number %>
                        <% else %>
                          <span class="text-zinc-400">—</span>
                        <% end %>
                      <% end %>
                    </p>
                  </div>

                  <div>
                    <p class="text-xs font-medium text-zinc-500 uppercase tracking-wider mb-2">
                      Message
                    </p>
                    <div class="bg-zinc-50 rounded-lg p-4 border border-zinc-200">
                      <%= if @selected_notification.rendered_message do %>
                        <div>
                          <%= raw(@selected_notification.rendered_message) %>
                        </div>
                      <% else %>
                        <p class="text-sm text-zinc-400 italic">No message content available</p>
                      <% end %>
                    </div>
                  </div>

                  <div :if={
                    @selected_notification.params && map_size(@selected_notification.params) > 0
                  }>
                    <p class="text-xs font-medium text-zinc-500 uppercase tracking-wider mb-2">
                      Parameters
                    </p>
                    <div class="bg-zinc-50 rounded-lg p-4 border border-zinc-200">
                      <pre class="text-xs text-zinc-600 overflow-x-auto"><code><%= inspect(@selected_notification.params, pretty: true) %></code></pre>
                    </div>
                  </div>
                </div>
              </div>
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
     |> assign(:ticket_orders_meta, nil)
     |> assign(:bookings_meta, nil)
     |> assign(:notifications, [])
     |> assign(:selected_notification, nil)
     |> assign(:panel_width, nil)
     |> assign(form: to_form(user_changeset, as: "user"))}
  end

  def handle_params(params, _uri, socket) do
    user_id = socket.assigns.user_id

    socket =
      case socket.assigns.live_action do
        :orders ->
          load_ticket_orders(socket, user_id, params)

        :bookings ->
          load_bookings(socket, user_id, params)

        :notifications ->
          load_notifications(socket, user_id)

        _ ->
          socket
      end

    {:noreply, socket}
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

  defp load_ticket_orders(socket, user_id, params) do
    case Tickets.list_user_ticket_orders_paginated(user_id, params) do
      {:ok, {orders, meta}} ->
        socket
        |> assign(:ticket_orders_meta, meta)
        |> stream(:ticket_orders, orders, reset: true)

      {:error, meta} ->
        socket
        |> assign(:ticket_orders_meta, meta)
        |> stream(:ticket_orders, [], reset: true)
    end
  end

  defp load_bookings(socket, user_id, params) do
    case Bookings.list_user_bookings_paginated(user_id, params) do
      {:ok, {bookings, meta}} ->
        socket
        |> assign(:bookings_meta, meta)
        |> stream(:bookings, bookings, reset: true)

      {:error, meta} ->
        socket
        |> assign(:bookings_meta, meta)
        |> stream(:bookings, [], reset: true)
    end
  end

  defp load_notifications(socket, user_id) do
    notifications = Messages.list_user_messages(user_id, limit: 100)
    assign(socket, :notifications, notifications)
  end

  def handle_event("select_notification", %{"id" => id}, socket) do
    notification =
      socket.assigns.notifications
      |> Enum.find(fn n -> n.id == id end)

    {:noreply, assign(socket, :selected_notification, notification)}
  end

  def handle_event("close_notification_panel", _params, socket) do
    {:noreply, assign(socket, :selected_notification, nil)}
  end

  def handle_event("resize_panel", %{"width" => width}, socket) do
    {:noreply, assign(socket, :panel_width, width)}
  end
end
