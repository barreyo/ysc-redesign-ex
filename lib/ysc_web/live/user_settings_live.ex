defmodule YscWeb.UserSettingsLive do
  use YscWeb, :live_view

  alias Ysc.Accounts
  alias Bling.Customers

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
          <h2 class="text-2xl font-semibold leading-8 text-zinc-800 mb-4">
            Setup Payment Method
          </h2>

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
              <!-- Display error message to your customers here -->
              <p id="card-errors" class="text-red-400 text-sm"></p>
            </div>
            <div id="payment-element">
              <!-- Elements will create form elements here -->
            </div>

            <div class="flex justify-end">
              <.button type="submit" id="submit">Save Payment Method</.button>
            </div>
          </form>
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
              href="#"
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
              href="#"
              class={[
                "inline-flex items-center px-4 py-3 rounded w-full",
                @live_action == :notifications && "bg-blue-600 active text-zinc-100",
                @live_action != :notifications && "hover:bg-zinc-100 hover:text-zinc-900"
              ]}
            >
              <.icon name="hero-bell-alert" class="w-5 h-5 me-2" />Notifications
            </.link>
          </li>
        </ul>

        <div class="p-6 text-medium text-zinc-500 rounded w-full md:border-l md:border-1 md:border-zinc-100 md:pl-16">
          <div :if={@live_action == :edit}>
            <.user_avatar_image
              email={@user.email}
              user_id={@user.id}
              country={@user.most_connected_country}
              class="w-20 rounded-full"
            />

            <p class="pt-4 text-sm">
              Your profile picture is synced via Gravatar. Update it on your <a
                class="text-blue-600 hover:underline"
                href="https://gravatar.com/profile"
                target="_blank"
                noreferrer
              >Gravatar Profile</a>.
            </p>

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
              <.input field={@password_form[:password]} type="password" label="New password" required />
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

          <div
            :if={@live_action == :membership || @live_action == :payment_method}
            class="flex flex-col space-y-6"
          >
            <div class="rounded border border-zinc-100 py-4 px-4 space-y-4">
              <div class="flex flex-row justify-between items-center">
                <h2 class="text-zinc-900 font-bold text-xl">Current Membership</h2>
              </div>

              <p :if={@current_membership == nil} class="text-sm text-zinc-600">
                You are currently <strong>not</strong> an active and paying member of the YSC.
              </p>

              <div
                :if={@current_membership != nil && Bling.Subscriptions.active?(@current_membership)}
                class="space-y-4"
              >
                <p class="text-sm text-zinc-600 font-semibold">
                  You have an
                  active <strong><%= get_membership_type(@current_membership) %></strong> membership.
                </p>

                <.button
                  phx-click="cancel-membership"
                  color="red"
                  disabled={!@user_is_active}
                  data-confirm="Are you sure you want to cancel your membership?"
                >
                  Cancel Membership
                </.button>
              </div>
            </div>

            <div class="rounded border border-zinc-100 py-4 px-4 space-y-4">
              <div class="flex flex-row justify-between items-center">
                <h2 class="text-zinc-900 font-bold text-xl">Manage Membership</h2>
              </div>

              <div :if={!@user_is_active} class="bg-yellow-50 border border-yellow-200 rounded-md p-4 mb-4">
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

              <div>
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
                          Enum.map(@membership_plans, fn plan ->
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

                    <div :if={@change_membership_button} class="flex w-full flex-row justify-end pt-4">
                      <.button
                        disabled={@default_payment_method == nil || !@user_is_active}
                        phx-click="change-membership"
                        type="button"
                      >
                        <.icon name="hero-arrows-right-left" class="me-2 -mt-0.5" />Change Membership Plan
                      </.button>
                    </div>
                  </div>

                  <div class="space-y-2">
                    <h3 class="text-lg font-semibold text-zinc-900">Payment Method</h3>

                    <div class="w-full py-2 px-3 bg-zinc-50 rounded">
                      <div class="w-full flex flex-row justify-between items-center">
                        <div class="items-center space-x-2 flex flex-row">
                          <svg
                            :if={@default_payment_method != nil}
                            stroke="currentColor"
                            fill="currentColor"
                            stroke-width="0"
                            viewBox="0 0 576 512"
                            xmlns="http://www.w3.org/2000/svg"
                            class="w-6 h-6 fill-zinc-800 text-zinc-800"
                          >
                            <path d={card_icon(@default_payment_method.card_brand)}></path>
                          </svg>

                          <span
                            :if={@default_payment_method != nil}
                            class="text-zinc-600 text-sm font-semibold"
                          >
                            **** **** **** <%= @default_payment_method.last_four %>
                          </span>
                          <span
                            :if={@default_payment_method == nil}
                            class="text-zinc-600 text-sm font-semibold"
                          >
                            No payment method
                          </span>
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

            <div class="rounded border border-zinc-100 px-4 py-4 space-y-4">
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
        :ok ->
          put_flash(socket, :info, "Email changed successfully.")

        :error ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    email_changeset = Accounts.change_user_email(user)
    password_changeset = Accounts.change_user_password(user)
    live_action = socket.assigns[:live_action] || :edit

    # Ensure Stripe customer exists - create if missing or invalid
    user = ensure_stripe_customer_exists(user)

    public_key = Application.get_env(:stripity_stripe, :public_key)
    default_payment_method = Bling.Customers.default_payment_method(user)
    membership_plans = Application.get_env(:ysc, :membership_plans)

    # Safely fetch invoices with error handling
    invoices = fetch_user_invoices(user)

    # This is all very dumb, but it's just a quick way to get the current membership status
    current_membership = socket.assigns.current_membership
    IO.inspect(current_membership)
    family_plan_active? = Bling.Customers.subscribed_to_price?(user, get_price_id(:family))

    active_plan = get_membership_plan(current_membership)

    IO.inspect(default_payment_method)

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
      |> assign(:invoices, invoices)
      |> assign(:change_membership_button, false)
      |> assign(:default_payment_method, default_payment_method)
      |> assign(:membership_plans, membership_plans)
      |> assign(:active_plan_type, active_plan)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(
        :membership_form,
        to_form(%{"membership_type" => default_select(family_plan_active?)})
      )
      |> assign(:trigger_submit, false)

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
        password_form =
          user
          |> Accounts.change_user_password(user_params)
          |> to_form()

        {:noreply, assign(socket, trigger_submit: true, password_form: password_form)}

      {:error, changeset} ->
        {:noreply, assign(socket, password_form: to_form(changeset))}
    end
  end

  def handle_event("select_membership", %{"membership_type" => membership_type} = _params, socket) do
    user = socket.assigns.user

    user =
      Accounts.get_user!(user.id, [:default_membership_payment_method])
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

      Bling.Customers.create_subscription(
        user,
        return_url: return_url,
        prices: [{price_id, 1}]
      )

      {:noreply, socket |> redirect(to: ~p"/users/membership")}
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

      {:noreply, socket |> assign(change_membership_button: change_membership_button)}
    end
  end

  def handle_event(
        "payment-method-set",
        %{"payment_method_id" => payment_method_id} = params,
        socket
      ) do
    IO.inspect(params)
    user = socket.assigns.user

    if user.state != :active do
      {:noreply,
       put_flash(
         socket,
         :error,
         "You must have an approved account to update your payment method."
       )}
    else
      {:noreply,
       socket
       |> put_flash(:info, "Payment method updated")
       |> push_navigate(to: ~p"/users/membership")}
    end
  end

  def handle_event("cancel-membership", _params, socket) do
    user = socket.assigns.user

    if user.state != :active do
      {:noreply,
       put_flash(socket, :error, "You must have an approved account to cancel your membership.")}
    else
      # TODO: Implement membership cancellation logic
      {:noreply,
       put_flash(socket, :info, "Membership cancellation functionality will be implemented soon.")}
    end
  end

  def handle_event("change-membership", _params, socket) do
    user = socket.assigns.user

    if user.state != :active do
      {:noreply,
       put_flash(
         socket,
         :error,
         "You must have an approved account to change your membership plan."
       )}
    else
      # TODO: Implement membership change logic
      {:noreply,
       put_flash(socket, :info, "Membership change functionality will be implemented soon.")}
    end
  end

  defp get_price_id(memberhip_type) do
    plans = Application.get_env(:ysc, :membership_plans)

    Enum.find(plans, &(&1.id == memberhip_type))[:stripe_price_id]
  end

  defp get_membership_plan(nil), do: nil

  defp get_membership_plan(%Subscription{stripe_status: "active"} = subscription) do
    item = Enum.at(subscription.subscription_items, 0)

    get_membership_type_from_price_id(item.stripe_price_id)
  end

  defp get_membership_plan(_), do: nil

  defp get_membership_type(subscription) do
    item = Enum.at(subscription.subscription_items, 0)

    get_membership_type_from_price_id(item.stripe_price_id)
  end

  defp get_membership_type_from_price_id(price_id) do
    plans = Application.get_env(:ysc, :membership_plans)

    Enum.find(plans, &(&1.stripe_price_id == price_id))[:id]
  end

  defp payment_to_badge_style("paid"), do: "green"
  defp payment_to_badge_style("open"), do: "blue"
  defp payment_to_badge_style("draft"), do: "yellow"
  defp payment_to_badge_style("uncollectible"), do: "red"
  defp payment_to_badge_style("void"), do: "red"
  defp payment_to_badge_style(_), do: "blue"

  defp default_select(true), do: "family"
  defp default_select(false), do: "single"

  defp payment_secret(:payment_method, user) do
    payment_method_intent =
      Bling.Customers.create_setup_intent(user,
        stripe: %{
          payment_method_types: ["card", "us_bank_account"]
        }
      )

    payment_method_intent.client_secret
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

  # Helper function to ensure Stripe customer exists
  defp ensure_stripe_customer_exists(user) do
    cond do
      # No stripe_id - create new customer
      user.stripe_id == nil ->
        Bling.Customers.create_stripe_customer(user)
        # Reload user to get updated stripe_id
        Ysc.Repo.get!(Ysc.Accounts.User, user.id)

      # Has stripe_id - verify customer exists in Stripe
      true ->
        case verify_stripe_customer_exists(user.stripe_id) do
          :ok ->
            user

          {:error, _} ->
            # Customer doesn't exist in Stripe, create a new one
            Bling.Customers.create_stripe_customer(user)
            # Reload user to get updated stripe_id
            Ysc.Repo.get!(Ysc.Accounts.User, user.id)
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
  defp fetch_user_invoices(user) do
    try do
      Customers.invoices(user)
      |> Enum.map(fn invoice ->
        %{
          hosted_invoice_url: invoice.hosted_invoice_url,
          created: invoice.created |> DateTime.from_unix!() |> DateTime.to_date(),
          total: invoice.total,
          currency: invoice.currency,
          status: invoice.status
        }
      end)
    rescue
      # Handle any errors when fetching invoices (e.g., customer not found)
      _error ->
        []
    end
  end
end
