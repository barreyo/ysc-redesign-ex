defmodule YscWeb.UserSettingsLive do
  use YscWeb, :live_view

  alias Ysc.Accounts
  alias Bling.Subscriptions
  alias Bling.Customers

  def render(assigns) do
    ~H"""
    <div class="max-w-screen-lg px-4 mx-auto py-6 lg:py-10">
      <div class="md:flex md:flex-row md:flex-auto md:grow container mx-auto">
        <ul class="flex-column space-y space-y-4 md:pr-10 text-sm font-medium text-zinc-600 md:me-4 mb-4 md:mb-0">
          <li>
            <h2 class="text-zinc-800 text-2xl font-semibold leading-8 mb-10">Settings</h2>
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
                @live_action == :membership && "bg-blue-600 active text-zinc-100",
                @live_action != :membership && "hover:bg-zinc-100 hover:text-zinc-900"
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

          <div :if={@live_action == :membership} class="flex flex-col space-y-6">
            <div class="rounded border border-zinc-100 py-4 px-4 space-y-4">
              <div class="flex flex-row justify-between items-center">
                <h2 class="text-zinc-900 font-bold text-xl">Current Membership</h2>
                <.button>Select Membership</.button>
              </div>

              <p :if={@current_membership == nil} class="text-sm text-zinc-700">
                You are currently not a paying member
              </p>
            </div>

            <div class="rounded border border-zinc-100 px-4 py-4 space-y-4">
              <h2 class="text-zinc-900 font-bold text-xl">Payment Method</h2>

              <div class="w-full py-2 px-3 bg-zinc-50 rounded">
                <%!-- <p class="text-zinc-800">n/a</p> --%>

                <div class="w-full flex flex-row justify-between items-center">
                  <div class="items-center space-x-2">
                    <.icon name="hero-credit-card" class="w-6 h-6" />
                    <span class="text-zinc-600 text-sm font-semibold">**** **** **** 4242</span>
                  </div>

                  <.button>Update</.button>
                </div>
              </div>
            </div>

            <div class="rounded border border-zinc-100 px-4 py-4 space-y-4">
              <h2 class="text-zinc-900 font-bold text-xl">Billing History</h2>

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
                      <%= Ysc.MoneyHelper.format_money!(Money.new(:USD, invoice.total)) %>
                    </div>
                  </div>

                  <.button>View</.button>
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

  def mount(params, _session, socket) do
    user = socket.assigns.current_user
    email_changeset = Accounts.change_user_email(user)
    password_changeset = Accounts.change_user_password(user)

    if user.stripe_id == nil do
      Bling.Customers.create_stripe_customer(user)
    end

    payment_method_intent = Bling.Customers.create_setup_intent(user)

    invoices =
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

    invoices = [
      %{
        hosted_invoice_url: "https://example.com",
        created: DateTime.utc_now() |> DateTime.to_date(),
        total: 10,
        currency: "usd",
        status: "paid"
      },
      %{
        hosted_invoice_url: "https://example.com",
        created: DateTime.utc_now() |> DateTime.to_date(),
        total: 10,
        currency: "usd",
        status: "paid"
      },
      %{
        hosted_invoice_url: "https://example.com",
        created: DateTime.utc_now() |> DateTime.to_date(),
        total: 10,
        currency: "usd",
        status: "paid"
      }
    ]

    IO.inspect(payment_method_intent)

    socket =
      socket
      |> assign(:page_title, "User Settings")
      |> assign(:current_password, nil)
      |> assign(:user, user)
      |> assign(:email_form_current_password, nil)
      |> assign(:current_email, user.email)
      |> assign(:invoices, invoices)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
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

  defp payment_to_badge_style("paid"), do: "green"
  defp payment_to_badge_style("open"), do: "blue"
  defp payment_to_badge_style("draft"), do: "yellow"
  defp payment_to_badge_style("uncollectible"), do: "red"
  defp payment_to_badge_style("void"), do: "red"
  defp payment_to_badge_style(_), do: "blue"
end
