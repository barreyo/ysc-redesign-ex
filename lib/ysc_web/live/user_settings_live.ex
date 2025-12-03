defmodule YscWeb.UserSettingsLive do
  use YscWeb, :live_view

  alias Ysc.Accounts
  alias Ysc.Accounts.UserNotifier
  alias Ysc.Customers
  alias Ysc.Ledgers
  alias Ysc.Repo
  alias Ysc.Subscriptions

  alias Ysc.Subscriptions.Subscription

  def render(assigns) do
    ~H"""
    <div class="max-w-screen-lg px-4 mx-auto py-8 lg:py-10">
      <div class="md:flex md:flex-row md:flex-auto md:grow container mx-auto">
        <.modal
          :if={@live_action == :payment_method}
          id="update-payment-method-modal"
          on_cancel={JS.navigate(~p"/users/membership")}
          show
        >
          <h2 class="text-2xl font-semibold leading-8 text-zinc-800 mb-6">
            Update Payment Method
          </h2>

          <div class="space-y-6">
            <!-- Existing Payment Methods -->
            <div :if={length(@all_payment_methods) > 0}>
              <h3 class="text-lg font-medium text-zinc-900 mb-4">Select Existing Payment Method</h3>
              <div class="space-y-3">
                <div
                  :for={payment_method <- @all_payment_methods}
                  class={[
                    "border rounded-lg p-4 transition-all duration-200",
                    @selecting_payment_method && "cursor-not-allowed opacity-50",
                    !@selecting_payment_method && "cursor-pointer",
                    @default_payment_method && payment_method.id == @default_payment_method.id &&
                      "border-blue-500 bg-blue-50",
                    (!@default_payment_method || payment_method.id != @default_payment_method.id) &&
                      !@selecting_payment_method && "border-zinc-200 hover:border-zinc-300"
                  ]}
                  phx-click={if @selecting_payment_method, do: nil, else: "select-payment-method"}
                  phx-value-payment_method_id={payment_method.id}
                >
                  <div class="flex items-center space-x-3">
                    <div class="flex-shrink-0">
                      <svg
                        :if={payment_method.type == :card}
                        stroke="currentColor"
                        fill="currentColor"
                        stroke-width="0"
                        viewBox="0 0 576 512"
                        xmlns="http://www.w3.org/2000/svg"
                        class="w-6 h-6 fill-zinc-800 text-zinc-800"
                      >
                        <path d={payment_method_icon(payment_method)}></path>
                      </svg>
                      <svg
                        :if={payment_method.type == :bank_account}
                        xmlns="http://www.w3.org/2000/svg"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke-width="1.5"
                        stroke="currentColor"
                        class="w-6 h-6 text-zinc-800"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d={payment_method_icon(payment_method)}
                        >
                        </path>
                      </svg>
                    </div>
                    <div class="flex-1 min-w-0">
                      <p class="text-zinc-600 text-sm font-semibold">
                        <%= payment_method_display_text(payment_method) %>
                      </p>
                      <p
                        :if={
                          payment_method.type == :card && payment_method.exp_month &&
                            payment_method.exp_year
                        }
                        class="text-zinc-600 text-xs"
                      >
                        Expires <%= String.pad_leading(to_string(payment_method.exp_month), 2, "0") %> / <%= payment_method.exp_year %>
                      </p>
                      <p
                        :if={payment_method.type == :bank_account && payment_method.account_type}
                        class="text-zinc-600 text-xs"
                      >
                        <%= payment_method.account_type %>
                      </p>
                    </div>
                    <div class="flex-shrink-0">
                      <div
                        :if={
                          @default_payment_method && payment_method.id == @default_payment_method.id
                        }
                        class="flex items-center text-blue-600"
                      >
                        <svg class="w-5 h-5 mr-1" fill="currentColor" viewBox="0 0 20 20">
                          <path
                            fill-rule="evenodd"
                            d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
                            clip-rule="evenodd"
                          >
                          </path>
                        </svg>
                        <span class="text-sm font-medium">Default</span>
                      </div>
                      <div
                        :if={
                          !@default_payment_method || payment_method.id != @default_payment_method.id
                        }
                        class="text-sm text-zinc-400"
                      >
                        <span :if={!@selecting_payment_method}>Click to set as default</span>
                        <span :if={@selecting_payment_method}>Updating...</span>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
            <!-- Add New Payment Method -->
            <div class="border-t flex w-full justify-end">
              <button
                :if={!@show_new_payment_form}
                id="add-payment-method"
                type="button"
                phx-click="add-new-payment-method"
                class="mt-3 inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
              >
                <svg class="-ml-1 mr-2 h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M12 6v6m0 0v6m0-6h6m-6 0H6"
                  >
                  </path>
                </svg>
                Add New Payment Method
              </button>
            </div>
          </div>
          <!-- New Payment Method Form (Hidden by default) -->
          <div :if={@show_new_payment_form && @payment_intent_secret} class="pt-4">
            <h3 class="text-lg font-medium text-zinc-900">Add New Payment Method</h3>
            <form
              id="payment-form"
              class="flex space-y-6 flex-col"
              phx-hook="StripeInput"
              data-clientSecret={@payment_intent_secret}
              data-publicKey={@public_key}
              data-submitURL={"#{YscWeb.Endpoint.url()}/billing/user/#{@user.id}/payment-method"}
              data-returnURL={"#{YscWeb.Endpoint.url()}/billing/user/#{@user.id}/finalize"}
            >
              <div id="error-message">
                <p id="card-errors" class="text-red-400 text-sm"></p>
              </div>
              <div id="payment-element">
                <!-- Elements will create form elements here -->
              </div>

              <div class="flex justify-end space-x-3">
                <button
                  type="button"
                  phx-click="cancel-new-payment-method"
                  class="px-4 py-2 border border-zinc-300 rounded-md text-sm font-medium text-zinc-700 bg-white hover:bg-zinc-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  id="submit"
                  class="px-4 py-2 border border-transparent rounded-md text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                >
                  Save Payment Method
                </button>
              </div>
            </form>
          </div>
        </.modal>

        <ul class="flex-column space-y space-y-4 md:pr-10 text-sm font-medium text-zinc-600 md:me-4 mb-4 md:mb-0">
          <li>
            <h2 class="text-zinc-800 text-2xl font-semibold leading-8 mb-10">Account</h2>
          </li>
          <li>
            <.link
              navigate={~p"/users/settings"}
              class={[
                "inline-flex items-center px-4 py-3 rounded w-full",
                @live_action == :edit && "bg-blue-600 active text-zinc-100",
                @live_action != :edit && "hover:bg-zinc-100 hover:text-zinc-900"
              ]}
              aria-active={@live_action == :edit}
            >
              <.icon name="hero-user" class="w-5 h-5 me-2" /> Profile
            </.link>
          </li>
          <li>
            <.link
              navigate={~p"/users/membership"}
              class={[
                "inline-flex items-center px-4 py-3 rounded w-full",
                (@live_action == :membership || @live_action == :payment_method) &&
                  "bg-blue-600 active text-zinc-100",
                @live_action != :membership && @live_action != :payment_method &&
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
                @live_action == :payments && "bg-blue-600 active text-zinc-100",
                @live_action != :payments && "hover:bg-zinc-100 hover:text-zinc-900"
              ]}
            >
              <.icon name="hero-wallet" class="w-5 h-5 me-2" /> Payments
            </.link>
          </li>
          <li>
            <.link
              navigate={~p"/users/notifications"}
              class={[
                "inline-flex items-center px-4 py-3 rounded w-full",
                @live_action == :notifications && "bg-blue-600 active text-zinc-100",
                @live_action != :notifications && "hover:bg-zinc-100 hover:text-zinc-900"
              ]}
            >
              <.icon name="hero-bell-alert" class="w-5 h-5 me-2" /> Notifications
            </.link>
          </li>
        </ul>

        <div class="text-medium px-2 text-zinc-500 rounded w-full md:border-l md:border-1 md:border-zinc-100 md:pl-16">
          <div :if={@live_action == :edit} class="space-y-8">
            <!-- Profile Picture Section -->
            <div class="rounded border border-zinc-100 py-4 px-4 space-y-4">
              <h2 class="text-zinc-900 font-bold text-xl">Profile Picture</h2>

              <div class="flex items-center space-x-4">
                <.user_avatar_image
                  email={@user.email}
                  user_id={@user.id}
                  country={@user.most_connected_country}
                  class="w-20 rounded-full"
                />
                <div>
                  <p class="text-sm text-zinc-600">
                    Your profile picture is synced via Gravatar. Update it on your <a
                      class="text-blue-600 hover:underline"
                      href="https://gravatar.com/profile"
                      target="_blank"
                      noreferrer
                    >Gravatar Profile</a>.
                  </p>
                </div>
              </div>
            </div>
            <!-- Personal Information Section -->
            <div class="rounded border border-zinc-100 py-4 px-4 space-y-4">
              <h2 class="text-zinc-900 font-bold text-xl">Personal Information</h2>

              <.simple_form
                for={@profile_form}
                id="profile_form"
                phx-submit="update_profile"
                phx-change="validate_profile"
              >
                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <.input field={@profile_form[:first_name]} type="text" label="First Name" required />
                  <.input field={@profile_form[:last_name]} type="text" label="Last Name" required />
                </div>

                <.input
                  type="phone-input"
                  label="Phone Number"
                  id="phone_number"
                  field={@profile_form[:phone_number]}
                />
                <p class="text-xs text-zinc-600 mt-1">
                  By providing your phone number, you consent to receive SMS notifications from YSC, including account updates, event reminders, and other important communications. Message and data rates may apply. You can opt out at any time in your notification settings. See our
                  <.link navigate={~p"/privacy-policy"} class="text-blue-600 hover:underline">
                    Privacy Policy
                  </.link>
                  for more information.
                </p>

                <.input
                  field={@profile_form[:most_connected_country]}
                  type="select"
                  label="Most Connected Country"
                  options={[
                    {"Sweden", "SE"},
                    {"Norway", "NO"},
                    {"Denmark", "DK"},
                    {"Finland", "FI"},
                    {"Iceland", "IS"}
                  ]}
                />

                <:actions>
                  <.button phx-disable-with="Updating...">Update Profile</.button>
                </:actions>
              </.simple_form>
            </div>
            <!-- Billing Address Section -->
            <div class="rounded border border-zinc-100 py-4 px-4 space-y-4">
              <h2 class="text-zinc-900 font-bold text-xl">Billing Address</h2>

              <.simple_form
                for={@address_form}
                id="address_form"
                phx-submit="update_address"
                phx-change="validate_address"
              >
                <.input field={@address_form[:address]} type="text" label="Street Address" required />

                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <.input field={@address_form[:city]} type="text" label="City" required />
                  <.input
                    field={@address_form[:postal_code]}
                    type="text"
                    label="Postal Code"
                    required
                  />
                </div>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <.input field={@address_form[:region]} type="text" label="State/Province/Region" />
                  <.input field={@address_form[:country]} type="text" label="Country" required />
                </div>

                <:actions>
                  <.button phx-disable-with="Updating...">Update Address</.button>
                </:actions>
              </.simple_form>
            </div>
            <!-- Account Security Section -->
            <div class="rounded border border-zinc-100 py-4 px-4 space-y-4">
              <h2 class="text-zinc-900 font-bold text-xl">Account Security</h2>

              <div class="space-y-6">
                <.simple_form
                  for={@email_form}
                  id="email_form"
                  phx-submit="update_email"
                  phx-change="validate_email"
                >
                  <.input field={@email_form[:email]} type="email" label="Email" required />
                  <.input
                    field={@email_form[:current_password]}
                    name="current_password"
                    id="current_password_for_email"
                    type="password"
                    label="Current password"
                    value={@email_form_current_password}
                    required
                  />
                  <:actions>
                    <.button phx-disable-with="Changing...">Change Email</.button>
                  </:actions>
                </.simple_form>

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
                    type="password"
                    label="New password"
                    required
                  />
                  <.input
                    field={@password_form[:password_confirmation]}
                    type="password"
                    label="Confirm new password"
                  />
                  <.input
                    field={@password_form[:current_password]}
                    name="current_password"
                    type="password"
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

          <div
            :if={@live_action == :membership || @live_action == :payment_method}
            class="flex flex-col space-y-6"
          >
            <div class="rounded border border-zinc-100 py-4 px-4 space-y-4">
              <div class="flex flex-row justify-between items-center">
                <h2 class="text-zinc-900 font-bold text-xl">Current Membership</h2>
              </div>

              <p :if={@current_membership == nil} class="text-sm text-zinc-600">
                <.icon name="hero-x-circle" class="me-1 w-5 h-5 text-red-600 -mt-0.5" />You are currently
                <strong>not</strong>
                an active and paying member of the YSC.
              </p>

              <.membership_status current_membership={@current_membership} />

              <div class="space-y-4">
                <.button
                  :if={
                    @current_membership != nil &&
                      !Subscriptions.scheduled_for_cancellation?(@current_membership) &&
                      @active_plan_type != :lifetime
                  }
                  phx-click="cancel-membership"
                  color="red"
                  disabled={
                    !@user_is_active || Subscriptions.scheduled_for_cancellation?(@current_membership)
                  }
                  data-confirm="Are you sure you want to cancel your membership?"
                >
                  Cancel Membership
                </.button>

                <.button
                  :if={Subscriptions.scheduled_for_cancellation?(@current_membership)}
                  phx-click="reactivate-membership"
                  color="green"
                  disabled={!@user_is_active}
                >
                  Reactivate Membership
                </.button>
              </div>
            </div>

            <div class="rounded border border-zinc-100 py-4 px-4 space-y-4">
              <div class="flex flex-row justify-between items-center">
                <h2 class="text-zinc-900 font-bold text-xl">Manage Membership</h2>
              </div>

              <div
                :if={@active_plan_type == :lifetime}
                class="bg-blue-50 border border-blue-200 rounded-md p-4 mb-4"
              >
                <div class="flex">
                  <div class="flex-shrink-0">
                    <.icon name="hero-star" class="h-5 w-5 text-blue-400" />
                  </div>
                  <div class="ml-3">
                    <h3 class="text-sm font-medium text-blue-800">
                      Lifetime Membership
                    </h3>
                    <div class="mt-2 text-sm text-blue-700">
                      <p>
                        You have a lifetime membership that never expires. Your membership cannot be cancelled or changed.
                      </p>
                    </div>
                  </div>
                </div>
              </div>

              <div
                :if={!@user_is_active}
                class="bg-yellow-50 border border-yellow-200 rounded-md p-4 mb-4"
              >
                <div class="flex">
                  <div class="flex-shrink-0">
                    <.icon name="hero-exclamation-triangle" class="h-5 w-5 text-yellow-400" />
                  </div>
                  <div class="ml-3">
                    <h3 class="text-sm font-medium text-yellow-800">
                      Account Pending Approval
                    </h3>
                    <div class="mt-2 text-sm text-yellow-700">
                      <p>
                        You will be able to manage your membership plan once your account is approved.
                        Please wait for the board to review and approve your application.
                      </p>
                    </div>
                  </div>
                </div>
              </div>

              <div :if={@active_plan_type != :lifetime}>
                <.form
                  for={@membership_form}
                  id="membership_form"
                  phx-submit="select_membership"
                  phx-change="validate_membership"
                  class={[
                    "space-y-6 pt-4",
                    !@user_is_active && "opacity-50 pointer-events-none"
                  ]}
                >
                  <div class="space-y-2">
                    <div class="flex flex-row items-center">
                      <h3 class="text-lg font-semibold text-zinc-900">Membership Type</h3>
                      <.dropdown
                        :if={@live_action != :payment_method}
                        id="membership-help"
                        wide={true}
                      >
                        <:button_block>
                          <.icon
                            class="w-5 h-5 text-blue-700 hover:text-blue-800 transition ease-in-out cursor-help"
                            name="hero-question-mark-circle"
                          />
                        </:button_block>

                        <div class="space-y-2 prose prose-zinc py-3 px-4">
                          <p class="text-sm">
                            The YSC offers two types of memberships: a <strong>Single</strong>
                            membership for individuals and a <strong>Family</strong>
                            membership that covers you, your spouse, and your children under 18. Both memberships are billed annually.
                          </p>

                          <p class="text-sm">
                            With the Family membership you can for example book "member" event tickets for everyone in your household. While the Single membership only allows you to book "member" event tickets for yourself.
                          </p>
                        </div>
                      </.dropdown>
                    </div>

                    <fieldset class="flex flex-wrap mb-8">
                      <.radio_fieldset
                        field={@membership_form[:membership_type]}
                        options={
                          @membership_plans
                          |> Enum.filter(&(&1.id != :lifetime))
                          |> Enum.map(fn plan ->
                            {plan.id,
                             %{
                               option: "#{plan.id}",
                               subtitle: plan.description,
                               icon: (plan.id == :single && "user") || "user-group",
                               footer:
                                 "#{Ysc.MoneyHelper.format_money!(Money.new(:USD, plan.amount))} per year"
                             }}
                          end)
                        }
                        checked_value={@membership_form.params["membership_type"]}
                      />
                    </fieldset>

                    <div
                      :if={@membership_change_info != nil}
                      class={[
                        "rounded-lg p-4 border mb-4",
                        if(@membership_change_info.direction == :upgrade,
                          do: "bg-blue-50 border-blue-200",
                          else: "bg-amber-50 border-amber-200"
                        )
                      ]}
                    >
                      <div class="flex">
                        <div class="flex-shrink-0">
                          <.icon
                            name={
                              if(@membership_change_info.direction == :upgrade,
                                do: "hero-arrow-trending-up",
                                else: "hero-arrow-trending-down"
                              )
                            }
                            class={[
                              "h-5 w-5",
                              if(@membership_change_info.direction == :upgrade,
                                do: "text-blue-400",
                                else: "text-amber-400"
                              )
                            ]}
                          />
                        </div>
                        <div class="ml-3 flex-1">
                          <h4 class={[
                            "text-sm font-semibold mb-2",
                            if(@membership_change_info.direction == :upgrade,
                              do: "text-blue-900",
                              else: "text-amber-900"
                            )
                          ]}>
                            <%= if @membership_change_info.direction == :upgrade do %>
                              Upgrade to <%= String.capitalize(
                                "#{@membership_change_info.new_plan.id}"
                              ) %> Membership
                            <% else %>
                              Downgrade to <%= String.capitalize(
                                "#{@membership_change_info.new_plan.id}"
                              ) %> Membership
                            <% end %>
                          </h4>
                          <div class={[
                            "text-sm space-y-1",
                            if(@membership_change_info.direction == :upgrade,
                              do: "text-blue-800",
                              else: "text-amber-800"
                            )
                          ]}>
                            <%= if @membership_change_info.direction == :upgrade do %>
                              <p>
                                You will be charged a prorated amount immediately to upgrade from <%= String.capitalize(
                                  "#{@membership_change_info.current_plan.id}"
                                ) %> to <%= String.capitalize(
                                  "#{@membership_change_info.new_plan.id}"
                                ) %> membership.
                              </p>
                              <p class="text-xs mt-2 opacity-90">
                                The prorated charge will be calculated based on the remaining time in your current billing period. The maximum charge will be
                                <strong>
                                  <%= Ysc.MoneyHelper.format_money!(
                                    Money.new(:USD, @membership_change_info.price_difference)
                                  ) %>
                                </strong>
                                (the full annual difference), but will be less based on how much time remains in your current period.
                              </p>
                            <% else %>
                              <p>
                                Your membership will change from <%= String.capitalize(
                                  "#{@membership_change_info.current_plan.id}"
                                ) %> to <%= String.capitalize(
                                  "#{@membership_change_info.new_plan.id}"
                                ) %> at your next renewal date.
                              </p>
                              <p class="text-xs mt-2 opacity-90">
                                You will continue to have <%= String.capitalize(
                                  "#{@membership_change_info.current_plan.id}"
                                ) %> benefits until then. No immediate charges or credits will be applied.
                              </p>
                            <% end %>
                          </div>
                        </div>
                      </div>
                    </div>

                    <div :if={@change_membership_button} class="flex w-full flex-row justify-end pt-4">
                      <.button
                        disabled={@default_payment_method == nil || !@user_is_active}
                        phx-click="change-membership"
                        phx-value-membership_type={@membership_form.params["membership_type"]}
                        type="button"
                      >
                        <.icon name="hero-arrows-right-left" class="me-2 -mt-0.5" />Change Membership Plan
                      </.button>
                    </div>
                  </div>

                  <div class="space-y-2">
                    <h3 class="text-lg font-semibold text-zinc-900">Payment Method</h3>

                    <div class="w-full py-2 px-3 rounded border border-zinc-200">
                      <div class="w-full flex flex-row justify-between items-center">
                        <div class="items-center space-x-2 flex flex-row">
                          <div :if={@default_payment_method != nil} class="flex-shrink-0">
                            <svg
                              :if={@default_payment_method.type == :card}
                              stroke="currentColor"
                              fill="currentColor"
                              stroke-width="0"
                              viewBox="0 0 576 512"
                              xmlns="http://www.w3.org/2000/svg"
                              class="w-6 h-6 fill-zinc-800 text-zinc-800"
                            >
                              <path d={payment_method_icon(@default_payment_method)}></path>
                            </svg>
                            <svg
                              :if={@default_payment_method.type == :bank_account}
                              xmlns="http://www.w3.org/2000/svg"
                              fill="none"
                              viewBox="0 0 24 24"
                              stroke-width="1.5"
                              stroke="currentColor"
                              class="w-6 h-6 text-zinc-800"
                            >
                              <path
                                stroke-linecap="round"
                                stroke-linejoin="round"
                                d={payment_method_icon(@default_payment_method)}
                              >
                              </path>
                            </svg>
                          </div>

                          <div class="flex flex-col">
                            <p
                              :if={@default_payment_method != nil}
                              class="text-zinc-600 text-sm font-semibold"
                            >
                              <%= payment_method_display_text(@default_payment_method) %>
                            </p>
                            <p
                              :if={
                                @default_payment_method != nil &&
                                  @default_payment_method.type == :card
                              }
                              class="text-zinc-600 text-xs"
                            >
                              Expires <%= String.pad_leading(
                                to_string(@default_payment_method.exp_month),
                                2,
                                "0"
                              ) %> / <%= @default_payment_method.exp_year %>
                            </p>
                            <p
                              :if={
                                @default_payment_method != nil &&
                                  @default_payment_method.type == :bank_account
                              }
                              class="text-zinc-600 text-xs"
                            >
                              <%= @default_payment_method.account_type %>
                            </p>
                            <p
                              :if={@default_payment_method == nil}
                              class="text-zinc-600 text-sm font-semibold"
                            >
                              No payment method
                            </p>
                          </div>
                        </div>

                        <.button
                          disabled={!@user_is_active}
                          phx-click={JS.navigate(~p"/users/membership/payment-method")}
                        >
                          Update Payment Method
                        </.button>
                      </div>
                    </div>
                  </div>

                  <div class="flex w-full justify-end pt-4">
                    <.button
                      :if={@active_plan_type == nil}
                      disabled={@default_payment_method == nil || !@user_is_active}
                    >
                      <.icon name="hero-credit-card" class="me-2 -mt-0.5" />Pay Membership
                    </.button>
                  </div>
                </.form>
              </div>
            </div>

            <%!-- <div class="rounded border border-zinc-100 px-4 py-4 space-y-4">
              <h2 class="text-zinc-900 font-bold text-xl">Membership Billing History</h2>

              <div class="space-y-3">
                <p :if={length(@invoices) == 0} class="text-zinc-600 text-sm">No previous payments</p>

                <div
                  :for={invoice <- @invoices}
                  class="items-center flex w-full flex-row justify-between rounded bg-zinc-50 py-2 px-3"
                >
                  <div>
                    <div class="flex flex-row space-x-2 items-center">
                      <p class="text-sm font-bold text-zinc-800">
                        <%= Timex.format!(invoice.created, "{Mshort} {D}, {YYYY}") %>
                      </p>
                      <.badge type={payment_to_badge_style(invoice.status)}>
                        <%= String.upcase(invoice.status) %>
                      </.badge>
                    </div>

                    <div class="text-sm text-zinc-600">
                      <%= Ysc.MoneyHelper.format_money!(Money.new(:USD, "#{invoice.total / 100.0}")) %>
                    </div>
                  </div>

                  <.button phx-click={JS.navigate(invoice.hosted_invoice_url)}>View</.button>
                </div>
              </div>
            </div> --%>
          </div>

          <div :if={@live_action == :notifications} class="space-y-6">
            <div class="rounded border border-zinc-100 py-4 px-4 space-y-4">
              <h2 class="text-zinc-900 font-bold text-xl">Notification Preferences</h2>
              <p class="text-sm text-zinc-600">
                Manage how you receive notifications from the YSC. You can control which types of notifications you receive via email or SMS.
              </p>
              <div class="bg-blue-50 border border-blue-200 rounded-lg p-4 mt-4">
                <p class="text-sm text-blue-900">
                  <strong>SMS Consent:</strong>
                  By enabling SMS notifications, you consent to receive text messages from YSC. Message and data rates may apply. You can opt out at any time by unchecking the SMS options below. See our
                  <.link
                    navigate={~p"/privacy-policy"}
                    class="text-blue-700 hover:underline font-semibold"
                  >
                    Privacy Policy
                  </.link>
                  for more information about how we use your phone number.
                </p>
              </div>

              <.simple_form
                for={@notification_form}
                id="notification_form"
                phx-submit="update_notifications"
                phx-change="validate_notifications"
              >
                <div class="overflow-x-auto">
                  <table class="min-w-full divide-y divide-zinc-200">
                    <thead class="bg-zinc-50">
                      <tr>
                        <th
                          scope="col"
                          class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider"
                        >
                          Category
                        </th>
                        <th
                          scope="col"
                          class="px-6 py-3 text-center text-xs font-medium text-zinc-500 uppercase tracking-wider"
                        >
                          Email
                        </th>
                        <th
                          scope="col"
                          class="px-6 py-3 text-center text-xs font-medium text-zinc-500 uppercase tracking-wider"
                        >
                          SMS
                        </th>
                      </tr>
                    </thead>
                    <tbody class="bg-white divide-y divide-zinc-200">
                      <!-- Newsletter Row -->
                      <tr>
                        <td class="px-6 py-4">
                          <div>
                            <div class="text-sm font-medium text-zinc-900">Newsletters</div>
                            <div class="text-sm text-zinc-500 mt-1">
                              Receive our newsletter with updates about YSC events, news, and community highlights.
                            </div>
                          </div>
                        </td>
                        <td class="px-6 py-4">
                          <input
                            type="hidden"
                            name={@notification_form[:newsletter_notifications].name}
                            value="false"
                          />
                          <.input
                            field={@notification_form[:newsletter_notifications]}
                            type="checkbox"
                            class="h-4 w-4 text-blue-600 focus:ring-blue-500 border-zinc-300 rounded"
                          />
                        </td>
                        <td class="px-6 py-4">
                          <span class="text-sm text-zinc-400">—</span>
                        </td>
                      </tr>
                      <!-- Event Updates Row -->
                      <tr>
                        <td class="px-6 py-4">
                          <div>
                            <div class="text-sm font-medium text-zinc-900">Event Updates</div>
                            <div class="text-sm text-zinc-500 mt-1">
                              Receive notifications when new events are published and reminders before events you're attending.
                            </div>
                          </div>
                        </td>
                        <td class="px-6 py-4">
                          <input
                            type="hidden"
                            name={@notification_form[:event_notifications].name}
                            value="false"
                          />
                          <.input
                            field={@notification_form[:event_notifications]}
                            type="checkbox"
                            class="h-4 w-4 text-blue-600 focus:ring-blue-500 border-zinc-300 rounded"
                          />
                        </td>
                        <td class="px-6 py-4">
                          <input
                            type="hidden"
                            name={@notification_form[:event_notifications_sms].name}
                            value="false"
                          />
                          <.input
                            field={@notification_form[:event_notifications_sms]}
                            type="checkbox"
                            class="h-4 w-4 text-blue-600 focus:ring-blue-500 border-zinc-300 rounded"
                          />
                        </td>
                      </tr>
                      <!-- Account Updates Row -->
                      <tr>
                        <td class="px-6 py-4">
                          <div>
                            <div class="text-sm font-medium text-zinc-900">Account Updates</div>
                            <div class="text-sm text-zinc-500 mt-1">
                              Important account-related notifications such as password changes, email confirmations, and security alerts.
                            </div>
                          </div>
                        </td>
                        <td class="px-6 py-4">
                          <input
                            type="hidden"
                            name={@notification_form[:account_notifications].name}
                            value="true"
                          />
                          <input
                            type="checkbox"
                            id={@notification_form[:account_notifications].id}
                            name={@notification_form[:account_notifications].name}
                            value="true"
                            checked={true}
                            disabled
                            class="h-4 w-4 text-zinc-600 focus:ring-blue-500 border-zinc-300 rounded opacity-50 cursor-not-allowed"
                          />
                        </td>
                        <td class="px-6 py-4">
                          <input
                            type="hidden"
                            name={@notification_form[:account_notifications_sms].name}
                            value="false"
                          />
                          <.input
                            field={@notification_form[:account_notifications_sms]}
                            type="checkbox"
                            class="h-4 w-4 text-blue-600 focus:ring-blue-500 border-zinc-300 rounded"
                          />
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>

                <:actions>
                  <.button phx-disable-with="Saving...">Save Preferences</.button>
                </:actions>
              </.simple_form>
            </div>
          </div>

          <div :if={@live_action == :payments} class="space-y-6">
            <div class="rounded border border-zinc-100 py-4 px-4 space-y-4">
              <h2 class="text-zinc-900 font-bold text-xl">Payment History</h2>

              <div :if={@payments_total > 0} id="payments-list" class="space-y-4">
                <div
                  :for={payment_info <- @payments}
                  class="border border-zinc-200 rounded-lg p-4 hover:bg-zinc-50 transition-colors"
                >
                  <div class="flex flex-row justify-between items-start">
                    <div class="flex-1">
                      <div class="flex items-center space-x-3 mb-2">
                        <.icon
                          :if={payment_info.type == :membership}
                          name="hero-heart"
                          class="w-5 h-5 text-blue-600"
                        />
                        <.icon
                          :if={payment_info.type == :ticket}
                          name="hero-ticket"
                          class="w-5 h-5 text-green-600"
                        />
                        <.icon
                          :if={payment_info.type == :booking}
                          name="hero-home"
                          class="w-5 h-5 text-purple-600"
                        />
                        <.icon
                          :if={payment_info.type == :donation}
                          name="hero-gift"
                          class="w-5 h-5 text-yellow-600"
                        />
                        <.icon
                          :if={payment_info.type == :unknown}
                          name="hero-credit-card"
                          class="w-5 h-5 text-zinc-600"
                        />
                        <div class="flex-1">
                          <h3 class="text-lg font-semibold text-zinc-900">
                            <%= payment_info.description %>
                          </h3>
                        </div>
                      </div>
                      <!-- Payment Details -->
                      <div class="space-y-2 text-sm text-zinc-600">
                        <!-- Event/Ticket Details -->
                        <div :if={payment_info.type == :ticket && payment_info.ticket_order}>
                          <div class="flex items-start space-x-2">
                            <span class="font-medium text-zinc-700">Event:</span>
                            <div class="flex-1">
                              <p class="text-zinc-900">
                                <%= if payment_info.event do
                                  payment_info.event.title
                                else
                                  "Event"
                                end %>
                              </p>
                              <p class="text-xs text-zinc-500 mt-1">
                                <%= if payment_info.ticket_order.tickets do
                                  tickets = payment_info.ticket_order.tickets

                                  tickets
                                  |> Enum.group_by(fn t -> t.ticket_tier && t.ticket_tier.name end)
                                  |> Enum.map(fn {tier_name, tier_tickets} ->
                                    count = length(tier_tickets)
                                    tier_display = tier_name || "General Admission"
                                    "#{count}x #{tier_display}"
                                  end)
                                  |> Enum.join(", ")
                                else
                                  "No ticket details"
                                end %>
                              </p>
                            </div>
                          </div>
                        </div>
                        <!-- Booking Details -->
                        <div :if={payment_info.type == :booking && payment_info.booking}>
                          <div class="space-y-1">
                            <div class="flex items-center space-x-2">
                              <span class="font-medium text-zinc-700">Property:</span>
                              <span class="text-zinc-900">
                                <%= case payment_info.booking.property do
                                  :tahoe -> "Tahoe"
                                  :clear_lake -> "Clear Lake"
                                  _ -> "Cabin"
                                end %>
                              </span>
                            </div>
                            <div class="flex items-center space-x-2">
                              <span class="font-medium text-zinc-700">Dates:</span>
                              <span class="text-zinc-900">
                                <%= Timex.format!(
                                  payment_info.booking.checkin_date,
                                  "{Mshort} {D}, {YYYY}"
                                ) %> - <%= Timex.format!(
                                  payment_info.booking.checkout_date,
                                  "{Mshort} {D}, {YYYY}"
                                ) %>
                              </span>
                              <span class="text-zinc-500">
                                (<%= Date.diff(
                                  payment_info.booking.checkout_date,
                                  payment_info.booking.checkin_date
                                ) %> nights)
                              </span>
                            </div>
                            <div
                              :if={
                                Ecto.assoc_loaded?(payment_info.booking.rooms) &&
                                  length(payment_info.booking.rooms) > 0
                              }
                              class="flex items-center space-x-2"
                            >
                              <span class="font-medium text-zinc-700">Rooms:</span>
                              <span class="text-zinc-900">
                                <%= Enum.map_join(payment_info.booking.rooms, ", ", fn room ->
                                  room.name
                                end) %>
                              </span>
                            </div>
                            <div class="flex items-center space-x-2">
                              <span class="font-medium text-zinc-700">Guests:</span>
                              <span class="text-zinc-900">
                                <%= payment_info.booking.guests_count %>
                                <%= if payment_info.booking.children_count > 0 do
                                  " (#{payment_info.booking.children_count} children)"
                                end %>
                              </span>
                            </div>
                            <div
                              :if={payment_info.booking.reference_id}
                              class="flex items-center space-x-2"
                            >
                              <span class="font-medium text-zinc-700">Booking ID:</span>
                              <code class="text-xs bg-zinc-100 px-2 py-0.5 rounded font-mono text-zinc-700">
                                <%= payment_info.booking.reference_id %>
                              </code>
                            </div>
                          </div>
                        </div>
                        <!-- Membership Details -->
                        <div :if={payment_info.type == :membership && payment_info.subscription}>
                          <div class="flex items-center space-x-2">
                            <span class="font-medium text-zinc-700">Plan:</span>
                            <span class="text-zinc-900">
                              <%= case payment_info.subscription.subscription_items do
                                [item | _] ->
                                  plans = Application.get_env(:ysc, :membership_plans)

                                  plan =
                                    Enum.find(plans, &(&1.stripe_price_id == item.stripe_price_id))

                                  if plan do
                                    String.capitalize(to_string(plan.id))
                                  else
                                    "Single"
                                  end

                                _ ->
                                  "Single"
                              end %>
                            </span>
                          </div>
                        </div>
                        <!-- Payment Information -->
                        <div class="flex items-center space-x-4 pt-2 border-t border-zinc-200">
                          <div>
                            <span class="font-medium text-zinc-700">Date:</span>
                            <span class="text-zinc-900 ml-1">
                              <%= if payment_info.payment.payment_date do
                                Timex.format!(
                                  payment_info.payment.payment_date,
                                  "{Mshort} {D}, {YYYY}"
                                )
                              else
                                Timex.format!(
                                  payment_info.payment.inserted_at,
                                  "{Mshort} {D}, {YYYY}"
                                )
                              end %>
                            </span>
                          </div>

                          <div>
                            <span class="font-medium text-zinc-700">Amount:</span>
                            <span class="text-zinc-900 font-semibold ml-1">
                              <%= Ysc.MoneyHelper.format_money!(payment_info.payment.amount) %>
                            </span>
                          </div>

                          <div>
                            <.badge :if={payment_info.payment.status == :completed} type="green">
                              Completed
                            </.badge>
                            <.badge :if={payment_info.payment.status == :pending} type="yellow">
                              Pending
                            </.badge>
                            <.badge :if={payment_info.payment.status == :refunded} type="red">
                              Refunded
                            </.badge>
                          </div>
                        </div>
                        <!-- Payment Method and Reference -->
                        <div class="flex items-center space-x-4 text-xs text-zinc-500 pt-1">
                          <div :if={payment_info.payment.reference_id}>
                            <span>Reference:</span>
                            <code class="ml-1 font-mono">
                              <%= payment_info.payment.reference_id %>
                            </code>
                          </div>
                          <div :if={
                            Ecto.assoc_loaded?(payment_info.payment.payment_method) &&
                              payment_info.payment.payment_method
                          }>
                            <span>Payment Method:</span>
                            <span class="ml-1">
                              <%= payment_method_display_text(payment_info.payment.payment_method) %>
                            </span>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <p :if={@payments_total == 0} class="text-zinc-600 text-sm">
                No payments found.
              </p>

              <div
                :if={@payments_total > 0}
                class="flex items-center justify-between border-t border-zinc-200 pt-4 mt-6"
              >
                <div class="flex items-center space-x-2">
                  <.button :if={@payments_page > 1} phx-click="prev-payments-page">
                    <.icon name="hero-chevron-left" class="w-4 h-4 me-1" /> Previous
                  </.button>
                </div>

                <div class="text-sm text-zinc-600">
                  Page <%= @payments_page %> of <%= @payments_total_pages %>
                </div>

                <div class="flex items-center space-x-2">
                  <.button :if={@payments_page < @payments_total_pages} phx-click="next-payments-page">
                    Next <.icon name="hero-chevron-right" class="w-4 h-4 ms-1" />
                  </.button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_user, token) do
        {:ok, updated_user, new_email} ->
          UserNotifier.deliver_email_changed_notification(updated_user, new_email)
          put_flash(socket, :info, "Email changed successfully.")

        :error ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    live_action = socket.assigns[:live_action] || :edit

    # Ensure Stripe customer exists - create if missing or invalid
    user = ensure_stripe_customer_exists(user)
    # Reload user with billing_address after ensure_stripe_customer_exists
    user = Repo.preload(user, :billing_address)

    email_changeset = Accounts.change_user_email(user)
    password_changeset = Accounts.change_user_password(user)
    profile_changeset = Accounts.change_user_profile(user)
    notification_changeset = Accounts.change_notification_preferences(user)
    address_changeset = Accounts.change_billing_address(user)

    public_key = Application.get_env(:stripity_stripe, :public_key)
    default_payment_method = Ysc.Payments.get_default_payment_method(user)

    all_payment_methods =
      Ysc.Payments.list_payment_methods(user)
      |> Enum.sort_by(fn pm -> {!pm.is_default, pm.inserted_at} end)

    membership_plans = Application.get_env(:ysc, :membership_plans)

    # Safely fetch invoices with error handling
    # invoices = fetch_user_invoices(user)

    # This is all very dumb, but it's just a quick way to get the current membership status
    current_membership = socket.assigns.current_membership
    family_plan_active? = Customers.subscribed_to_price?(user, get_price_id(:family))

    active_plan = get_membership_plan(current_membership)

    # Check if user is active to determine if they can manage membership
    user_is_active = user.state == :active

    socket =
      socket
      |> assign(:page_title, "User Settings")
      |> assign(:current_password, nil)
      |> assign(:user, user)
      |> assign(:user_is_active, user_is_active)
      |> assign(:payment_intent_secret, payment_secret(live_action, user))
      |> assign(:public_key, public_key)
      |> assign(:email_form_current_password, nil)
      |> assign(:current_email, user.email)
      # |> assign(:invoices, invoices)
      |> assign(:change_membership_button, false)
      |> assign(:membership_change_info, nil)
      |> assign(:default_payment_method, default_payment_method)
      |> assign(:all_payment_methods, all_payment_methods)
      |> assign(:show_new_payment_form, false)
      |> assign(:selecting_payment_method, false)
      |> assign(:membership_plans, membership_plans)
      |> assign(:active_plan_type, active_plan)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:profile_form, to_form(profile_changeset))
      |> assign(:notification_form, to_form(notification_changeset))
      |> assign(:address_form, to_form(address_changeset))
      |> assign(
        :membership_form,
        to_form(%{"membership_type" => default_select(family_plan_active?)})
      )
      |> assign(:trigger_submit, false)

    socket =
      if live_action == :payments do
        per_page = 20
        {payments, total_count} = Ledgers.list_user_payments_paginated(user.id, 1, per_page)
        total_pages = div(total_count + per_page - 1, per_page)

        socket
        |> assign(:payments_page, 1)
        |> assign(:payments_per_page, per_page)
        |> assign(:payments_total, total_count)
        |> assign(:payments_total_pages, total_pages)
        |> assign(:payments, payments)
      else
        socket
      end

    {:ok, socket}
  end

  def handle_event("validate_email", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    email_form =
      socket.assigns.current_user
      |> Accounts.change_user_email(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form, email_form_current_password: password)}
  end

  def handle_event("update_email", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.apply_user_email(user, password, user_params) do
      {:ok, applied_user} ->
        Accounts.deliver_user_update_email_instructions(
          applied_user,
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info) |> assign(email_form_current_password: nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, :email_form, to_form(Map.put(changeset, :action, :insert)))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    password_form =
      socket.assigns.current_user
      |> Accounts.change_user_password(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form, current_password: password)}
  end

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

  def handle_event("validate_profile", params, socket) do
    %{"user" => user_params} = params

    profile_form =
      socket.assigns.current_user
      |> Accounts.change_user_profile(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, profile_form: profile_form)}
  end

  def handle_event("update_profile", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.update_user_profile(user, user_params) do
      {:ok, updated_user} ->
        profile_form = Accounts.change_user_profile(updated_user, user_params) |> to_form()

        {:noreply,
         socket
         |> assign(:user, updated_user)
         |> assign(:profile_form, profile_form)
         |> put_flash(:info, "Profile updated successfully.")}

      {:error, changeset} ->
        {:noreply, assign(socket, profile_form: to_form(changeset))}
    end
  end

  def handle_event("validate_notifications", params, socket) do
    %{"user" => user_params} = params

    notification_form =
      socket.assigns.current_user
      |> Accounts.change_notification_preferences(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, notification_form: notification_form)}
  end

  def handle_event("update_notifications", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_user

    # Ensure account_notifications is always true
    user_params = Map.put(user_params, "account_notifications", "true")

    # Helper function to convert form checkbox value to boolean
    to_bool = fn
      "true" -> true
      true -> true
      _ -> false
    end

    # Check if newsletter preference changed
    old_newsletter_pref = user.newsletter_notifications

    case Accounts.update_notification_preferences(user, user_params) do
      {:ok, updated_user} ->
        # Sync with Mailpoet if newsletter preference changed
        new_newsletter_pref = to_bool.(user_params["newsletter_notifications"])

        if old_newsletter_pref != new_newsletter_pref do
          sync_mailpoet_subscription(updated_user, new_newsletter_pref)
        end

        notification_form =
          Accounts.change_notification_preferences(updated_user, user_params) |> to_form()

        {:noreply,
         socket
         |> assign(:user, updated_user)
         |> assign(:notification_form, notification_form)
         |> put_flash(:info, "Notification preferences updated successfully.")}

      {:error, changeset} ->
        {:noreply, assign(socket, notification_form: to_form(changeset))}
    end
  end

  def handle_event("validate_address", params, socket) do
    %{"address" => address_params} = params
    user = socket.assigns.current_user

    address_form =
      user
      |> Accounts.change_billing_address(address_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, address_form: address_form)}
  end

  def handle_event("update_address", params, socket) do
    %{"address" => address_params} = params
    user = socket.assigns.current_user

    case Accounts.update_billing_address(user, address_params) do
      {:ok, _address} ->
        # Reload user with updated address
        updated_user = Accounts.get_user!(user.id, [:billing_address])
        address_form = Accounts.change_billing_address(updated_user) |> to_form()

        {:noreply,
         socket
         |> assign(:user, updated_user)
         |> assign(:address_form, address_form)
         |> put_flash(:info, "Billing address updated successfully.")}

      {:error, changeset} ->
        {:noreply, assign(socket, address_form: to_form(changeset))}
    end
  end

  def handle_event("select_membership", %{"membership_type" => membership_type} = _params, socket) do
    user = socket.assigns.user

    user =
      Accounts.get_user!(user.id)
      |> Accounts.User.populate_virtual_fields()

    if user.state != :active do
      {:noreply,
       put_flash(
         socket,
         :error,
         "You must have an approved account to manage your membership plan."
       )}
    else
      membership_atom = String.to_existing_atom(membership_type)
      return_url = url(~p"/billing/user/#{user.id}/finalize")
      price_id = get_price_id(membership_atom)
      default_payment_method = socket.assigns.default_payment_method

      case Customers.create_subscription(
             user,
             return_url: return_url,
             prices: [%{price: price_id, quantity: 1}],
             default_payment_method: default_payment_method.provider_id,
             expand: ["latest_invoice"]
           ) do
        {:ok, stripe_subscription} ->
          # Also save the subscription locally as a backup in case webhook fails
          case Ysc.Subscriptions.create_subscription_from_stripe(user, stripe_subscription) do
            {:ok, _local_subscription} ->
              {:noreply,
               socket
               |> put_flash(:info, "Membership activated successfully!")
               |> redirect(to: ~p"/users/membership")}

            {:error, reason} ->
              require Logger

              Logger.warning("Failed to save subscription locally, webhook should handle it",
                user_id: user.id,
                stripe_subscription_id: stripe_subscription.id,
                error: reason
              )

              {:noreply,
               socket
               |> put_flash(:info, "Membership activated successfully!")
               |> redirect(to: ~p"/users/membership")}
          end

        {:error, error} ->
          require Logger

          Logger.error("Failed to create subscription",
            user_id: user.id,
            error: error
          )

          {:noreply,
           socket |> put_flash(:error, "Failed to activate membership. Please try again.")}
      end
    end
  end

  def handle_event(
        "validate_membership",
        %{"membership_type" => membership_type} = _params,
        socket
      ) do
    user = socket.assigns.user

    if user.state != :active do
      {:noreply, socket}
    else
      assigns = socket.assigns
      membership_atom = String.to_existing_atom(membership_type)

      change_membership_button =
        assigns.active_plan_type != nil &&
          assigns.active_plan_type !=
            membership_atom

      # Calculate change information if a different plan is selected
      change_info =
        if change_membership_button && assigns.active_plan_type != nil do
          plans = assigns.membership_plans
          current_plan = Enum.find(plans, &(&1.id == assigns.active_plan_type))
          new_plan = Enum.find(plans, &(&1.id == membership_atom))

          if current_plan && new_plan do
            direction = if new_plan.amount > current_plan.amount, do: :upgrade, else: :downgrade
            price_difference = abs(new_plan.amount - current_plan.amount)

            %{
              direction: direction,
              current_plan: current_plan,
              new_plan: new_plan,
              price_difference: price_difference
            }
          else
            nil
          end
        else
          nil
        end

      {:noreply,
       socket
       |> assign(change_membership_button: change_membership_button)
       |> assign(:membership_change_info, change_info)
       |> assign(:membership_form, to_form(%{"membership_type" => membership_type}))}
    end
  end

  def handle_event(
        "payment-method-set",
        %{"payment_method_id" => payment_method_id},
        socket
      ) do
    user = socket.assigns.user

    if user.state != :active do
      {:noreply,
       put_flash(
         socket,
         :error,
         "You must have an approved account to update your payment method."
       )}
    else
      # Retrieve the payment method from Stripe and store it locally
      case Stripe.PaymentMethod.retrieve(payment_method_id) do
        {:ok, stripe_payment_method} ->
          # Store the payment method in our database and set it as default
          case Ysc.Payments.upsert_and_set_default_payment_method_from_stripe(
                 user,
                 stripe_payment_method
               ) do
            {:ok, _} ->
              # Update Stripe customer to use this payment method as default
              case Stripe.Customer.update(user.stripe_id, %{
                     invoice_settings: %{default_payment_method: payment_method_id}
                   }) do
                {:ok, _stripe_customer} ->
                  # Reload user and payment methods to get updated info
                  updated_user = Ysc.Accounts.get_user!(user.id)
                  updated_payment_methods = Ysc.Payments.list_payment_methods(updated_user)
                  updated_default = Ysc.Payments.get_default_payment_method(updated_user)

                  {:noreply,
                   socket
                   |> assign(:user, updated_user)
                   |> assign(:all_payment_methods, updated_payment_methods)
                   |> assign(:default_payment_method, updated_default)
                   |> assign(:show_new_payment_form, false)
                   |> put_flash(:info, "Payment method updated and set as default")
                   |> redirect(to: ~p"/users/membership")}

                {:error, stripe_error} ->
                  {:noreply,
                   put_flash(
                     socket,
                     :error,
                     "Payment method saved but failed to set as default in Stripe: #{stripe_error.message}"
                   )}
              end

            {:error, _reason} ->
              {:noreply,
               put_flash(
                 socket,
                 :error,
                 "Failed to store payment method"
               )}
          end

        {:error, _reason} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "Failed to retrieve payment method from Stripe"
           )}
      end
    end
  end

  def handle_event("select-payment-method", %{"payment_method_id" => payment_method_id}, socket) do
    user = socket.assigns.user

    if user.state != :active do
      {:noreply,
       put_flash(
         socket,
         :error,
         "You must have an approved account to update your payment method."
       )}
    else
      # Prevent multiple clicks
      if socket.assigns.selecting_payment_method do
        {:noreply, socket}
      else
        # Find the payment method in the current list
        selected_payment_method =
          Enum.find(socket.assigns.all_payment_methods, &(&1.id == payment_method_id))

        if selected_payment_method do
          # Optimistically update the UI first
          updated_payment_methods =
            Enum.map(socket.assigns.all_payment_methods, fn pm ->
              if pm.id == payment_method_id do
                # Use Ecto.Changeset to properly update the struct
                pm
                |> Ysc.Payments.PaymentMethod.changeset(%{is_default: true})
                |> Ecto.Changeset.apply_changes()
              else
                # Use Ecto.Changeset to properly update the struct
                pm
                |> Ysc.Payments.PaymentMethod.changeset(%{is_default: false})
                |> Ecto.Changeset.apply_changes()
              end
            end)

          socket =
            socket
            |> assign(:selecting_payment_method, true)
            |> assign(:all_payment_methods, updated_payment_methods)
            |> assign(:default_payment_method, selected_payment_method)

          # Then perform the actual database operations
          require Logger

          Logger.info("Setting payment method as default",
            user_id: user.id,
            payment_method_id: selected_payment_method.id,
            provider_id: selected_payment_method.provider_id
          )

          case Ysc.Payments.set_default_payment_method(user, selected_payment_method) do
            {:ok, _} ->
              Logger.info("Successfully set payment method as default in database",
                user_id: user.id,
                payment_method_id: selected_payment_method.id
              )

              # Update Stripe customer to use this payment method as default
              Logger.info("Updating Stripe customer default payment method",
                user_id: user.id,
                stripe_customer_id: user.stripe_id,
                default_payment_method_id: selected_payment_method.provider_id
              )

              case Stripe.Customer.update(user.stripe_id, %{
                     invoice_settings: %{
                       default_payment_method: selected_payment_method.provider_id
                     }
                   }) do
                {:ok, _stripe_customer} ->
                  Logger.info("Successfully updated Stripe customer default payment method",
                    user_id: user.id,
                    stripe_customer_id: user.stripe_id
                  )

                  # Don't reload from database immediately to avoid race conditions with webhooks
                  # The optimistic update should be sufficient for the UI
                  # Skip the delayed refresh for now to prevent overriding our optimistic update

                  {:noreply,
                   socket
                   |> assign(:selecting_payment_method, false)
                   |> put_flash(:info, "Payment method set as default")}

                {:error, stripe_error} ->
                  # Revert optimistic update on error
                  original_payment_methods =
                    Enum.map(socket.assigns.all_payment_methods, fn pm ->
                      if pm.id == socket.assigns.default_payment_method.id do
                        pm
                        |> Ysc.Payments.PaymentMethod.changeset(%{is_default: true})
                        |> Ecto.Changeset.apply_changes()
                      else
                        pm
                        |> Ysc.Payments.PaymentMethod.changeset(%{is_default: false})
                        |> Ecto.Changeset.apply_changes()
                      end
                    end)

                  {:noreply,
                   socket
                   |> assign(:all_payment_methods, original_payment_methods)
                   |> assign(:selecting_payment_method, false)
                   |> put_flash(
                     :error,
                     "Failed to update default payment method in Stripe: #{stripe_error.message}"
                   )}
              end

            {:error, _reason} ->
              # Revert optimistic update on error
              original_payment_methods =
                Enum.map(socket.assigns.all_payment_methods, fn pm ->
                  if pm.id == socket.assigns.default_payment_method.id do
                    pm
                    |> Ysc.Payments.PaymentMethod.changeset(%{is_default: true})
                    |> Ecto.Changeset.apply_changes()
                  else
                    pm
                    |> Ysc.Payments.PaymentMethod.changeset(%{is_default: false})
                    |> Ecto.Changeset.apply_changes()
                  end
                end)

              {:noreply,
               socket
               |> assign(:all_payment_methods, original_payment_methods)
               |> assign(:selecting_payment_method, false)
               |> put_flash(
                 :error,
                 "Failed to set payment method as default"
               )}
          end
        else
          {:noreply,
           put_flash(
             socket,
             :error,
             "Payment method not found"
           )}
        end
      end
    end
  end

  def handle_event("add-new-payment-method", _params, socket) do
    require Logger
    user = socket.assigns.user

    Logger.info("Creating setup intent for user", user_id: user.id, stripe_id: user.stripe_id)

    # Ensure user has a Stripe customer ID (reload user if it was just created)
    user = ensure_stripe_customer_exists(user)

    if user.stripe_id == nil do
      Logger.error("User still has no stripe_id after ensure_stripe_customer_exists",
        user_id: user.id
      )

      {:noreply,
       socket
       |> put_flash(
         :error,
         "Failed to create payment account. Please try again or contact support."
       )
       |> assign(:show_new_payment_form, false)}
    else
      Logger.info("User has stripe_id, creating setup intent",
        user_id: user.id,
        stripe_id: user.stripe_id
      )

      case Customers.create_setup_intent(user,
             stripe: %{
               payment_method_types: ["us_bank_account", "card"]
             }
           ) do
        {:ok, setup_intent} ->
          Logger.info("Setup intent created successfully",
            setup_intent_id: setup_intent.id,
            has_client_secret: not is_nil(setup_intent.client_secret)
          )

          {:noreply,
           socket
           |> assign(:user, user)
           |> assign(:show_new_payment_form, true)
           |> assign(:payment_intent_secret, setup_intent.client_secret)}

        {:error, error} ->
          error_message =
            case error do
              %Stripe.Error{message: msg} -> msg
              %{message: msg} -> msg
              msg when is_binary(msg) -> msg
              other -> inspect(other, pretty: true)
            end

          Logger.error("Failed to create setup intent",
            user_id: user.id,
            stripe_id: user.stripe_id,
            error: error_message,
            full_error: inspect(error, pretty: true, limit: :infinity)
          )

          {:noreply,
           socket
           |> put_flash(:error, "Failed to initialize payment form: #{error_message}")
           |> assign(:show_new_payment_form, false)}
      end
    end
  end

  def handle_event("cancel-new-payment-method", _params, socket) do
    {:noreply, assign(socket, :show_new_payment_form, false)}
  end

  def handle_event("refresh-payment-methods", _params, socket) do
    user = socket.assigns.user

    # Use the new sync function to ensure we're in sync with Stripe
    {:ok, updated_payment_methods} = Ysc.Payments.sync_payment_methods_with_stripe(user)
    updated_default = Ysc.Payments.get_default_payment_method(user)

    {:noreply,
     socket
     |> assign(:all_payment_methods, updated_payment_methods)
     |> assign(:default_payment_method, updated_default)}
  end

  def handle_event("cancel-membership", _params, socket) do
    user = socket.assigns.user

    if user.state != :active do
      {:noreply,
       put_flash(socket, :error, "You must have an approved account to cancel your membership.")}
    else
      # Schedule cancellation at end of current period in Stripe and persist locally
      case Subscriptions.cancel(socket.assigns.current_membership) do
        {:ok, _subscription} ->
          {:noreply,
           put_flash(socket, :info, "Membership cancelled.")
           |> redirect(to: ~p"/users/membership")}

        {:error, reason} when is_binary(reason) ->
          {:noreply, put_flash(socket, :error, reason)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to cancel membership. Please try again.")}
      end
    end
  end

  def handle_event("reactivate-membership", _params, socket) do
    user = socket.assigns.user

    if user.state != :active do
      {:noreply,
       put_flash(socket, :error, "You must have an approved account to cancel your membership.")}
    else
      case Subscriptions.resume(socket.assigns.current_membership) do
        {:error, reason} ->
          {:noreply, put_flash(socket, :error, reason)}

        {:ok, _subscription} ->
          {:noreply,
           put_flash(socket, :info, "Membership reactivated.")
           |> redirect(to: ~p"/users/membership")}

        _subscription ->
          {:noreply,
           put_flash(socket, :info, "Membership reactivated.")
           |> redirect(to: ~p"/users/membership")}
      end
    end
  end

  def handle_event("next-payments-page", _, socket) do
    current_page = socket.assigns.payments_page
    total_pages = socket.assigns.payments_total_pages

    if current_page < total_pages do
      {:noreply, paginate_payments(socket, current_page + 1)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("prev-payments-page", _, socket) do
    current_page = socket.assigns.payments_page

    if current_page > 1 do
      {:noreply, paginate_payments(socket, current_page - 1)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("change-membership", params, socket) do
    user = socket.assigns.user

    if user.state != :active do
      {:noreply,
       put_flash(
         socket,
         :error,
         "You must have an approved account to change your membership plan."
       )}
    else
      current_membership = socket.assigns.current_membership

      new_type =
        params["membership_type"] || socket.assigns.membership_form.params["membership_type"]

      cond do
        is_nil(new_type) or new_type == "" ->
          {:noreply, put_flash(socket, :error, "Please select a membership type first.")}

        is_nil(current_membership) ->
          {:noreply, put_flash(socket, :error, "You do not have an active membership to change.")}

        true ->
          # Determine current and new plan info
          current_type = get_membership_plan(current_membership)
          new_atom = String.to_existing_atom(new_type)

          if current_type == :lifetime do
            {:noreply, put_flash(socket, :error, "Lifetime memberships cannot be changed.")}
          else
            if new_atom == :lifetime do
              {:noreply,
               put_flash(
                 socket,
                 :error,
                 "Lifetime membership can only be awarded by an administrator."
               )}
            else
              if current_type == new_atom do
                {:noreply, put_flash(socket, :info, "You are already on that plan.")}
              else
                plans = Application.get_env(:ysc, :membership_plans)
                current_plan = Enum.find(plans, &(&1.id == current_type))
                new_plan = Enum.find(plans, &(&1.id == new_atom))

                new_price_id = new_plan[:stripe_price_id]

                direction =
                  if new_plan.amount > current_plan.amount, do: :upgrade, else: :downgrade

                case Subscriptions.change_membership_plan(
                       current_membership,
                       new_price_id,
                       direction
                     ) do
                  {:ok, updated_subscription} ->
                    # Reload subscription with items to get updated data from Stripe
                    updated_membership =
                      updated_subscription
                      |> Repo.preload(:subscription_items)

                    # Determine success message based on direction
                    success_message =
                      case direction do
                        :upgrade ->
                          "Your membership plan has been upgraded. You have been charged the prorated difference."

                        :downgrade ->
                          "Your membership plan change has been scheduled. The new price will take effect at your next renewal."
                      end

                    {:noreply,
                     socket
                     |> assign(:current_membership, updated_membership)
                     |> assign(:active_plan_type, new_atom)
                     |> assign(:change_membership_button, false)
                     |> assign(:membership_change_info, nil)
                     |> assign(
                       :membership_form,
                       to_form(%{"membership_type" => Atom.to_string(new_atom)})
                     )
                     |> put_flash(:info, success_message)
                     |> redirect(to: ~p"/users/membership")}

                  {:scheduled, _schedule} ->
                    {:noreply,
                     put_flash(
                       socket,
                       :info,
                       "Your membership plan will switch at your next renewal."
                     )
                     |> redirect(to: ~p"/users/membership")}

                  {:error, reason} ->
                    {:noreply,
                     put_flash(
                       socket,
                       :error,
                       "Failed to change membership: #{inspect(reason)}"
                     )}
                end
              end
            end
          end
      end
    end
  end

  def handle_info({:refresh_payment_methods, user_id}, socket) do
    if socket.assigns.user.id == user_id do
      user = socket.assigns.user

      # Use the new sync function to ensure we're in sync with Stripe
      {:ok, updated_payment_methods} = Ysc.Payments.sync_payment_methods_with_stripe(user)
      updated_default = Ysc.Payments.get_default_payment_method(user)

      require Logger

      Logger.info("Refreshed payment methods after selection",
        user_id: user.id,
        payment_methods_count: length(updated_payment_methods),
        default_payment_method_id: updated_default && updated_default.id
      )

      {:noreply,
       socket
       |> assign(:all_payment_methods, updated_payment_methods)
       |> assign(:default_payment_method, updated_default)}
    else
      {:noreply, socket}
    end
  end

  defp paginate_payments(socket, new_page) when new_page >= 1 do
    %{payments_per_page: per_page, payments_total: total_count, user: user} = socket.assigns
    {payments, _total_count} = Ledgers.list_user_payments_paginated(user.id, new_page, per_page)
    total_pages = div(total_count + per_page - 1, per_page)

    socket
    |> assign(:payments_page, new_page)
    |> assign(:payments_total_pages, total_pages)
    |> assign(:payments, payments)
  end

  defp sync_mailpoet_subscription(user, should_subscribe) do
    # Subscribe or unsubscribe from Mailpoet asynchronously
    # Failures are logged but don't affect preference update
    action = if should_subscribe, do: "subscribe", else: "unsubscribe"

    case %{"email" => user.email, "action" => action}
         |> YscWeb.Workers.MailpoetSubscriber.new()
         |> Oban.insert() do
      {:ok, _job} ->
        require Logger

        Logger.info("Mailpoet subscription sync job enqueued",
          user_id: user.id,
          email: user.email,
          action: action
        )

        :ok

      {:error, changeset} ->
        require Logger

        Logger.warning("Failed to enqueue Mailpoet subscription sync job",
          user_id: user.id,
          email: user.email,
          action: action,
          errors: inspect(changeset.errors)
        )

        :ok
    end
  end

  defp get_price_id(memberhip_type) do
    plans = Application.get_env(:ysc, :membership_plans)

    Enum.find(plans, &(&1.id == memberhip_type))[:stripe_price_id]
  end

  defp get_membership_plan(nil), do: nil

  defp get_membership_plan(%{type: :lifetime}), do: :lifetime

  defp get_membership_plan(%Subscription{stripe_status: "active"} = subscription) do
    item = Enum.at(subscription.subscription_items, 0)

    get_membership_type_from_price_id(item.stripe_price_id)
  end

  defp get_membership_plan(_), do: nil

  defp get_membership_type_from_price_id(price_id) do
    plans = Application.get_env(:ysc, :membership_plans)

    Enum.find(plans, &(&1.stripe_price_id == price_id))[:id]
  end

  # defp payment_to_badge_style("paid"), do: "green"
  # defp payment_to_badge_style("open"), do: "blue"
  # defp payment_to_badge_style("draft"), do: "yellow"
  # defp payment_to_badge_style("uncollectible"), do: "red"
  # defp payment_to_badge_style("void"), do: "red"
  # defp payment_to_badge_style(_), do: "blue"

  defp default_select(true), do: "family"
  defp default_select(false), do: "single"

  defp payment_secret(:payment_method, user) do
    case Customers.create_setup_intent(user,
           stripe: %{
             payment_method_types: ["us_bank_account", "card"]
           }
         ) do
      {:ok, setup_intent} -> setup_intent.client_secret
      {:error, _} -> nil
    end
  end

  defp payment_secret(_, _), do: nil

  defp card_icon("visa"),
    do:
      "M470.1 231.3s7.6 37.2 9.3 45H446c3.3-8.9 16-43.5 16-43.5-.2.3 3.3-9.1 5.3-14.9l2.8 13.4zM576 80v352c0 26.5-21.5 48-48 48H48c-26.5 0-48-21.5-48-48V80c0-26.5 21.5-48 48-48h480c26.5 0 48 21.5 48 48zM152.5 331.2L215.7 176h-42.5l-39.3 106-4.3-21.5-14-71.4c-2.3-9.9-9.4-12.7-18.2-13.1H32.7l-.7 3.1c15.8 4 29.9 9.8 42.2 17.1l35.8 135h42.5zm94.4.2L272.1 176h-40.2l-25.1 155.4h40.1zm139.9-50.8c.2-17.7-10.6-31.2-33.7-42.3-14.1-7.1-22.7-11.9-22.7-19.2.2-6.6 7.3-13.4 23.1-13.4 13.1-.3 22.7 2.8 29.9 5.9l3.6 1.7 5.5-33.6c-7.9-3.1-20.5-6.6-36-6.6-39.7 0-67.6 21.2-67.8 51.4-.3 22.3 20 34.7 35.2 42.2 15.5 7.6 20.8 12.6 20.8 19.3-.2 10.4-12.6 15.2-24.1 15.2-16 0-24.6-2.5-37.7-8.3l-5.3-2.5-5.6 34.9c9.4 4.3 26.8 8.1 44.8 8.3 42.2.1 69.7-20.8 70-53zM528 331.4L495.6 176h-31.1c-9.6 0-16.9 2.8-21 12.9l-59.7 142.5H426s6.9-19.2 8.4-23.3H486c1.2 5.5 4.8 23.3 4.8 23.3H528z"

  defp card_icon("mastercard"),
    do:
      "M482.9 410.3c0 6.8-4.6 11.7-11.2 11.7-6.8 0-11.2-5.2-11.2-11.7 0-6.5 4.4-11.7 11.2-11.7 6.6 0 11.2 5.2 11.2 11.7zm-310.8-11.7c-7.1 0-11.2 5.2-11.2 11.7 0 6.5 4.1 11.7 11.2 11.7 6.5 0 10.9-4.9 10.9-11.7-.1-6.5-4.4-11.7-10.9-11.7zm117.5-.3c-5.4 0-8.7 3.5-9.5 8.7h19.1c-.9-5.7-4.4-8.7-9.6-8.7zm107.8.3c-6.8 0-10.9 5.2-10.9 11.7 0 6.5 4.1 11.7 10.9 11.7 6.8 0 11.2-4.9 11.2-11.7 0-6.5-4.4-11.7-11.2-11.7zm105.9 26.1c0 .3.3.5.3 1.1 0 .3-.3.5-.3 1.1-.3.3-.3.5-.5.8-.3.3-.5.5-1.1.5-.3.3-.5.3-1.1.3-.3 0-.5 0-1.1-.3-.3 0-.5-.3-.8-.5-.3-.3-.5-.5-.5-.8-.3-.5-.3-.8-.3-1.1 0-.5 0-.8.3-1.1 0-.5.3-.8.5-1.1.3-.3.5-.3.8-.5.5-.3.8-.3 1.1-.3.5 0 .8 0 1.1.3.5.3.8.3 1.1.5s.2.6.5 1.1zm-2.2 1.4c.5 0 .5-.3.8-.3.3-.3.3-.5.3-.8 0-.3 0-.5-.3-.8-.3 0-.5-.3-1.1-.3h-1.6v3.5h.8V426h.3l1.1 1.4h.8l-1.1-1.3zM576 81v352c0 26.5-21.5 48-48 48H48c-26.5 0-48-21.5-48-48V81c0-26.5 21.5-48 48-48h480c26.5 0 48 21.5 48 48zM64 220.6c0 76.5 62.1 138.5 138.5 138.5 27.2 0 53.9-8.2 76.5-23.1-72.9-59.3-72.4-171.2 0-230.5-22.6-15-49.3-23.1-76.5-23.1-76.4-.1-138.5 62-138.5 138.2zm224 108.8c70.5-55 70.2-162.2 0-217.5-70.2 55.3-70.5 162.6 0 217.5zm-142.3 76.3c0-8.7-5.7-14.4-14.7-14.7-4.6 0-9.5 1.4-12.8 6.5-2.4-4.1-6.5-6.5-12.2-6.5-3.8 0-7.6 1.4-10.6 5.4V392h-8.2v36.7h8.2c0-18.9-2.5-30.2 9-30.2 10.2 0 8.2 10.2 8.2 30.2h7.9c0-18.3-2.5-30.2 9-30.2 10.2 0 8.2 10 8.2 30.2h8.2v-23zm44.9-13.7h-7.9v4.4c-2.7-3.3-6.5-5.4-11.7-5.4-10.3 0-18.2 8.2-18.2 19.3 0 11.2 7.9 19.3 18.2 19.3 5.2 0 9-1.9 11.7-5.4v4.6h7.9V392zm40.5 25.6c0-15-22.9-8.2-22.9-15.2 0-5.7 11.9-4.8 18.5-1.1l3.3-6.5c-9.4-6.1-30.2-6-30.2 8.2 0 14.3 22.9 8.3 22.9 15 0 6.3-13.5 5.8-20.7.8l-3.5 6.3c11.2 7.6 32.6 6 32.6-7.5zm35.4 9.3l-2.2-6.8c-3.8 2.1-12.2 4.4-12.2-4.1v-16.6h13.1V392h-13.1v-11.2h-8.2V392h-7.6v7.3h7.6V416c0 17.6 17.3 14.4 22.6 10.9zm13.3-13.4h27.5c0-16.2-7.4-22.6-17.4-22.6-10.6 0-18.2 7.9-18.2 19.3 0 20.5 22.6 23.9 33.8 14.2l-3.8-6c-7.8 6.4-19.6 5.8-21.9-4.9zm59.1-21.5c-4.6-2-11.6-1.8-15.2 4.4V392h-8.2v36.7h8.2V408c0-11.6 9.5-10.1 12.8-8.4l2.4-7.6zm10.6 18.3c0-11.4 11.6-15.1 20.7-8.4l3.8-6.5c-11.6-9.1-32.7-4.1-32.7 15 0 19.8 22.4 23.8 32.7 15l-3.8-6.5c-9.2 6.5-20.7 2.6-20.7-8.6zm66.7-18.3H408v4.4c-8.3-11-29.9-4.8-29.9 13.9 0 19.2 22.4 24.7 29.9 13.9v4.6h8.2V392zm33.7 0c-2.4-1.2-11-2.9-15.2 4.4V392h-7.9v36.7h7.9V408c0-11 9-10.3 12.8-8.4l2.4-7.6zm40.3-14.9h-7.9v19.3c-8.2-10.9-29.9-5.1-29.9 13.9 0 19.4 22.5 24.6 29.9 13.9v4.6h7.9v-51.7zm7.6-75.1v4.6h.8V302h1.9v-.8h-4.6v.8h1.9zm6.6 123.8c0-.5 0-1.1-.3-1.6-.3-.3-.5-.8-.8-1.1-.3-.3-.8-.5-1.1-.8-.5 0-1.1-.3-1.6-.3-.3 0-.8.3-1.4.3-.5.3-.8.5-1.1.8-.5.3-.8.8-.8 1.1-.3.5-.3 1.1-.3 1.6 0 .3 0 .8.3 1.4 0 .3.3.8.8 1.1.3.3.5.5 1.1.8.5.3 1.1.3 1.4.3.5 0 1.1 0 1.6-.3.3-.3.8-.5 1.1-.8.3-.3.5-.8.8-1.1.3-.6.3-1.1.3-1.4zm3.2-124.7h-1.4l-1.6 3.5-1.6-3.5h-1.4v5.4h.8v-4.1l1.6 3.5h1.1l1.4-3.5v4.1h1.1v-5.4zm4.4-80.5c0-76.2-62.1-138.3-138.5-138.3-27.2 0-53.9 8.2-76.5 23.1 72.1 59.3 73.2 171.5 0 230.5 22.6 15 49.5 23.1 76.5 23.1 76.4.1 138.5-61.9 138.5-138.4z"

  defp card_icon("amex"),
    do:
      "M0 432c0 26.5 21.5 48 48 48H528c26.5 0 48-21.5 48-48v-1.1H514.3l-31.9-35.1-31.9 35.1H246.8V267.1H181L262.7 82.4h78.6l28.1 63.2V82.4h97.2L483.5 130l17-47.6H576V80c0-26.5-21.5-48-48-48H48C21.5 32 0 53.5 0 80V432zm440.4-21.7L482.6 364l42 46.3H576l-68-72.1 68-72.1H525.4l-42 46.7-41.5-46.7H390.5L458 338.6l-67.4 71.6V377.1h-83V354.9h80.9V322.6H307.6V300.2h83V267.1h-122V410.3H440.4zm96.3-72L576 380.2V296.9l-39.3 41.4zm-36.3-92l36.9-100.6V246.3H576V103H515.8l-32.2 89.3L451.7 103H390.5V246.1L327.3 103H276.1L213.7 246.3h43l11.9-28.7h65.9l12 28.7h82.7V146L466 246.3h34.4zM282 185.4l19.5-46.9 19.4 46.9H282z"

  defp card_icon("discover"),
    do:
      "M520.4 196.1c0-7.9-5.5-12.1-15.6-12.1h-4.9v24.9h4.7c10.3 0 15.8-4.4 15.8-12.8zM528 32H48C21.5 32 0 53.5 0 80v352c0 26.5 21.5 48 48 48h480c26.5 0 48-21.5 48-48V80c0-26.5-21.5-48-48-48zm-44.1 138.9c22.6 0 52.9-4.1 52.9 24.4 0 12.6-6.6 20.7-18.7 23.2l25.8 34.4h-19.6l-22.2-32.8h-2.2v32.8h-16zm-55.9.1h45.3v14H444v18.2h28.3V217H444v22.2h29.3V253H428zm-68.7 0l21.9 55.2 22.2-55.2h17.5l-35.5 84.2h-8.6l-35-84.2zm-55.9-3c24.7 0 44.6 20 44.6 44.6 0 24.7-20 44.6-44.6 44.6-24.7 0-44.6-20-44.6-44.6 0-24.7 20-44.6 44.6-44.6zm-49.3 6.1v19c-20.1-20.1-46.8-4.7-46.8 19 0 25 27.5 38.5 46.8 19.2v19c-29.7 14.3-63.3-5.7-63.3-38.2 0-31.2 33.1-53 63.3-38zm-97.2 66.3c11.4 0 22.4-15.3-3.3-24.4-15-5.5-20.2-11.4-20.2-22.7 0-23.2 30.6-31.4 49.7-14.3l-8.4 10.8c-10.4-11.6-24.9-6.2-24.9 2.5 0 4.4 2.7 6.9 12.3 10.3 18.2 6.6 23.6 12.5 23.6 25.6 0 29.5-38.8 37.4-56.6 11.3l10.3-9.9c3.7 7.1 9.9 10.8 17.5 10.8zM55.4 253H32v-82h23.4c26.1 0 44.1 17 44.1 41.1 0 18.5-13.2 40.9-44.1 40.9zm67.5 0h-16v-82h16zM544 433c0 8.2-6.8 15-15 15H128c189.6-35.6 382.7-139.2 416-160zM74.1 191.6c-5.2-4.9-11.6-6.6-21.9-6.6H48v54.2h4.2c10.3 0 17-2 21.9-6.4 5.7-5.2 8.9-12.8 8.9-20.7s-3.2-15.5-8.9-20.5z"

  defp card_icon("jcb"),
    do:
      "M431.5 244.3V212c41.2 0 38.5.2 38.5.2 7.3 1.3 13.3 7.3 13.3 16 0 8.8-6 14.5-13.3 15.8-1.2.4-3.3.3-38.5.3zm42.8 20.2c-2.8-.7-3.3-.5-42.8-.5v35c39.6 0 40 .2 42.8-.5 7.5-1.5 13.5-8 13.5-17 0-8.7-6-15.5-13.5-17zM576 80v352c0 26.5-21.5 48-48 48H48c-26.5 0-48-21.5-48-48V80c0-26.5 21.5-48 48-48h480c26.5 0 48 21.5 48 48zM182 192.3h-57c0 67.1 10.7 109.7-35.8 109.7-19.5 0-38.8-5.7-57.2-14.8v28c30 8.3 68 8.3 68 8.3 97.9 0 82-47.7 82-131.2zm178.5 4.5c-63.4-16-165-14.9-165 59.3 0 77.1 108.2 73.6 165 59.2V287C312.9 311.7 253 309 253 256s59.8-55.6 107.5-31.2v-28zM544 286.5c0-18.5-16.5-30.5-38-32v-.8c19.5-2.7 30.3-15.5 30.3-30.2 0-19-15.7-30-37-31 0 0 6.3-.3-120.3-.3v127.5h122.7c24.3.1 42.3-12.9 42.3-33.2z"

  defp card_icon("diners"),
    do:
      "M239.7 79.9c-96.9 0-175.8 78.6-175.8 175.8 0 96.9 78.9 175.8 175.8 175.8 97.2 0 175.8-78.9 175.8-175.8 0-97.2-78.6-175.8-175.8-175.8zm-39.9 279.6c-41.7-15.9-71.4-56.4-71.4-103.8s29.7-87.9 71.4-104.1v207.9zm79.8.3V151.6c41.7 16.2 71.4 56.7 71.4 104.1s-29.7 87.9-71.4 104.1zM528 32H48C21.5 32 0 53.5 0 80v352c0 26.5 21.5 48 48 48h480c26.5 0 48-21.5 48-48V80c0-26.5-21.5-48-48-48zM329.7 448h-90.3c-106.2 0-193.8-85.5-193.8-190.2C45.6 143.2 133.2 64 239.4 64h90.3c105 0 200.7 79.2 200.7 193.8 0 104.7-95.7 190.2-200.7 190.2z"

  defp card_icon(_), do: "hero-credit-card"

  defp payment_method_icon(%{type: :card, display_brand: brand}), do: card_icon(brand)
  defp payment_method_icon(%{type: :bank_account}), do: bank_account_icon()
  defp payment_method_icon(_), do: "hero-credit-card"

  defp bank_account_icon(),
    do:
      "M2.25 18.75a60.07 60.07 0 0 1 15.797 2.101c.727.198 1.453-.342 1.453-1.096V18.75M3.75 4.5v.75A.75.75 0 0 1 3 6h-.75m0 0v-.375c0-.621.504-1.125 1.125-1.125H20.25M2.25 6v9m18-10.5v.75c0 .414.336.75.75.75h.75m-1.5-1.5h.375c.621 0 1.125.504 1.125 1.125v9.75c0 .621-.504 1.125-1.125 1.125h-.375m1.5-1.5H21a.75.75 0 0 0-.75.75v.75m0 0H3.75m0 0h-.375a1.125 1.125 0 0 1-1.125-1.125V15m1.5 1.5v-.75A.75.75 0 0 0 3 15h-.75M15 10.5a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm3 0h.008v.008H18V10.5Zm-12 0h.008v.008H6V10.5Z"

  defp payment_method_display_text(%{type: :card, last_four: last_four})
       when not is_nil(last_four) do
    "**** **** **** #{last_four}"
  end

  defp payment_method_display_text(%{
         type: :bank_account,
         bank_name: bank_name,
         account_type: _account_type,
         last_four: last_four
       })
       when not is_nil(bank_name) and not is_nil(last_four) do
    "#{bank_name} ••••#{last_four}"
  end

  defp payment_method_display_text(%{type: :bank_account, last_four: last_four})
       when not is_nil(last_four) do
    "Bank Account ••••#{last_four}"
  end

  defp payment_method_display_text(%{type: :card}) do
    "Credit Card"
  end

  defp payment_method_display_text(%{type: :bank_account}) do
    "Bank Account"
  end

  defp payment_method_display_text(_) do
    "Payment Method"
  end

  # Helper function to ensure Stripe customer exists
  defp ensure_stripe_customer_exists(user) do
    if user.stripe_id == nil do
      # No stripe_id - create new customer
      case Customers.create_stripe_customer(user) do
        {:ok, _stripe_customer} ->
          # Reload user to get updated stripe_id
          # Add a small delay to ensure the database update has committed
          Process.sleep(50)
          reloaded_user = Ysc.Accounts.get_user!(user.id)

          # If still no stripe_id after reload, try again (database might need a moment)
          if reloaded_user.stripe_id == nil do
            Process.sleep(100)
            Ysc.Accounts.get_user!(user.id)
          else
            reloaded_user
          end

        {:error, error} ->
          require Logger

          Logger.error("Failed to create Stripe customer",
            user_id: user.id,
            error: inspect(error)
          )

          user
      end
    else
      # Has stripe_id - verify customer exists in Stripe
      case verify_stripe_customer_exists(user.stripe_id) do
        :ok ->
          user

        {:error, _} ->
          # Customer doesn't exist in Stripe, create a new one
          case Customers.create_stripe_customer(user) do
            {:ok, _stripe_customer} ->
              # Reload user to get updated stripe_id
              # Add a small delay to ensure the database update has committed
              Process.sleep(50)
              reloaded_user = Ysc.Accounts.get_user!(user.id)

              # If still no stripe_id after reload, try again
              if reloaded_user.stripe_id == nil do
                Process.sleep(100)
                Ysc.Accounts.get_user!(user.id)
              else
                reloaded_user
              end

            {:error, error} ->
              require Logger

              Logger.error("Failed to create Stripe customer",
                user_id: user.id,
                error: inspect(error)
              )

              user
          end
      end
    end
  end

  # Helper function to verify if Stripe customer exists
  defp verify_stripe_customer_exists(stripe_id) do
    case Stripe.Customer.retrieve(stripe_id) do
      {:ok, _customer} -> :ok
      {:error, %Stripe.Error{code: :resource_missing}} -> {:error, :not_found}
      {:error, error} -> {:error, error}
    end
  end

  # Helper function to safely fetch user invoices
end
