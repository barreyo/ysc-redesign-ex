defmodule YscWeb.AdminMoneyLive do
  use YscWeb, :live_view

  alias Ysc.Ledgers
  alias Ysc.Accounts

  @impl true
  def mount(_params, _session, socket) do
    # Set default date range to current calendar year
    current_year = DateTime.utc_now().year
    start_date = DateTime.new!(Date.new!(current_year, 1, 1), ~T[00:00:00])
    end_date = DateTime.new!(Date.new!(current_year, 12, 31), ~T[23:59:59])

    accounts_with_balances = Ledgers.get_accounts_with_balances(start_date, end_date)
    recent_payments = Ledgers.get_recent_payments(start_date, end_date)

    {:ok,
     socket
     |> assign(:page_title, "Money")
     |> assign(:active_page, :money)
     |> assign(:accounts_with_balances, accounts_with_balances)
     |> assign(:recent_payments, recent_payments)
     |> assign(:start_date, start_date)
     |> assign(:end_date, end_date)
     |> assign(:show_refund_modal, false)
     |> assign(:show_credit_modal, false)
     |> assign(:selected_payment, nil)
     |> assign(:selected_user, nil)
     |> assign(:refund_form, to_form(%{}, as: :refund))
     |> assign(:credit_form, to_form(%{}, as: :credit))}
  end

  @impl true
  def handle_event("show_refund_modal", %{"payment_id" => payment_id}, socket) do
    payment = Ledgers.get_payment(payment_id)

    {:noreply,
     socket
     |> assign(:show_refund_modal, true)
     |> assign(:selected_payment, payment)
     |> assign(:refund_form, to_form(%{}, as: :refund))}
  end

  @impl true
  def handle_event("show_credit_modal", %{"user_id" => user_id}, socket) do
    user = Accounts.get_user!(user_id)

    {:noreply,
     socket
     |> assign(:show_credit_modal, true)
     |> assign(:selected_user, user)
     |> assign(:credit_form, to_form(%{}, as: :credit))}
  end

  @impl true
  def handle_event("close_refund_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_refund_modal, false)
     |> assign(:selected_payment, nil)}
  end

  @impl true
  def handle_event("close_credit_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_credit_modal, false)
     |> assign(:selected_user, nil)}
  end

  @impl true
  def handle_event("process_refund", %{"refund" => refund_params}, socket) do
    %{selected_payment: payment} = socket.assigns

    refund_attrs = %{
      payment_id: payment.id,
      refund_amount: Money.parse!(refund_params["amount"]),
      reason: refund_params["reason"],
      external_refund_id: "admin_refund_#{Ecto.ULID.generate()}"
    }

    case Ledgers.process_refund(refund_attrs) do
      {:ok, _transaction, _entries} ->
        # Refresh data with current date range
        %{start_date: start_date, end_date: end_date} = socket.assigns
        accounts_with_balances = Ledgers.get_accounts_with_balances(start_date, end_date)
        recent_payments = Ledgers.get_recent_payments(start_date, end_date)

        {:noreply,
         socket
         |> put_flash(:info, "Refund processed successfully")
         |> assign(:show_refund_modal, false)
         |> assign(:selected_payment, nil)
         |> assign(:accounts_with_balances, accounts_with_balances)
         |> assign(:recent_payments, recent_payments)}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to process refund")}
    end
  end

  @impl true
  def handle_event("process_credit", %{"credit" => credit_params}, socket) do
    %{selected_user: user} = socket.assigns

    credit_attrs = %{
      user_id: user.id,
      amount: Money.parse!(credit_params["amount"]),
      reason: credit_params["reason"],
      entity_type: String.to_atom(credit_params["entity_type"] || "administration"),
      entity_id: credit_params["entity_id"]
    }

    case Ledgers.add_credit(credit_attrs) do
      {:ok, _payment, _transaction, _entries} ->
        # Refresh data with current date range
        %{start_date: start_date, end_date: end_date} = socket.assigns
        accounts_with_balances = Ledgers.get_accounts_with_balances(start_date, end_date)
        recent_payments = Ledgers.get_recent_payments(start_date, end_date)

        {:noreply,
         socket
         |> put_flash(:info, "Credit added successfully")
         |> assign(:show_credit_modal, false)
         |> assign(:selected_user, nil)
         |> assign(:accounts_with_balances, accounts_with_balances)
         |> assign(:recent_payments, recent_payments)}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to add credit")}
    end
  end

  @impl true
  def handle_event("validate_refund", %{"refund" => refund_params}, socket) do
    changeset =
      %{}
      |> refund_changeset(refund_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :refund_form, to_form(changeset, as: :refund))}
  end

  @impl true
  def handle_event("validate_credit", %{"credit" => credit_params}, socket) do
    changeset =
      %{}
      |> credit_changeset(credit_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :credit_form, to_form(changeset, as: :credit))}
  end

  @impl true
  def handle_event(
        "update_date_range",
        %{"start_date" => start_date_str, "end_date" => end_date_str},
        socket
      ) do
    # Parse the date strings and convert to DateTime
    start_date = parse_date_to_datetime(start_date_str, ~T[00:00:00])
    end_date = parse_date_to_datetime(end_date_str, ~T[23:59:59])

    # Get updated data with new date range
    accounts_with_balances = Ledgers.get_accounts_with_balances(start_date, end_date)
    recent_payments = Ledgers.get_recent_payments(start_date, end_date)

    {:noreply,
     socket
     |> assign(:accounts_with_balances, accounts_with_balances)
     |> assign(:recent_payments, recent_payments)
     |> assign(:start_date, start_date)
     |> assign(:end_date, end_date)}
  end

  @impl true
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
          Money Management
        </h1>
      </div>
      <!-- Date Range Filter -->
      <div class="mb-6 bg-white p-4 rounded-lg shadow border">
        <h3 class="text-lg font-medium text-gray-900 mb-4">Date Range Filter</h3>
        <form phx-submit="update_date_range" class="flex gap-4 items-end">
          <div>
            <label for="start_date" class="block text-sm font-medium text-gray-700 mb-1">
              Start Date
            </label>
            <input
              type="date"
              id="start_date"
              name="start_date"
              value={Calendar.strftime(@start_date, "%Y-%m-%d")}
              class="block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
            />
          </div>
          <div>
            <label for="end_date" class="block text-sm font-medium text-gray-700 mb-1">
              End Date
            </label>
            <input
              type="date"
              id="end_date"
              name="end_date"
              value={Calendar.strftime(@end_date, "%Y-%m-%d")}
              class="block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
            />
          </div>
          <.button type="submit" class="bg-blue-600 hover:bg-blue-700">
            Update
          </.button>
        </form>
        <p class="text-sm text-gray-600 mt-2">
          Showing data from <%= Calendar.strftime(@start_date, "%B %d, %Y") %> to <%= Calendar.strftime(
            @end_date,
            "%B %d, %Y"
          ) %>
        </p>
      </div>
      <!-- Account Balances -->
      <div class="mb-8">
        <h2 class="text-xl font-semibold mb-4">Account Balances</h2>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <div
            :for={account_data <- @accounts_with_balances}
            class="bg-white p-4 rounded-lg shadow border"
          >
            <h3 class="font-medium text-gray-900"><%= account_data.account.name %></h3>
            <p class="text-sm text-gray-600"><%= account_data.account.description %></p>
            <p class="text-lg font-semibold mt-2">
              <%= Money.to_string!(account_data.balance || Money.new(0, :USD)) %>
            </p>
            <p class="text-xs text-gray-500 capitalize"><%= account_data.account.account_type %></p>
          </div>
        </div>
      </div>
      <!-- Quick Actions -->
      <div class="mb-8">
        <h2 class="text-xl font-semibold mb-4">Quick Actions</h2>
        <div class="flex gap-4">
          <.button
            phx-click="show_credit_modal"
            phx-value-user_id=""
            class="bg-green-600 hover:bg-green-700"
          >
            Add Credit
          </.button>
        </div>
      </div>
      <!-- Recent Payments -->
      <div class="mb-8">
        <h2 class="text-xl font-semibold mb-4">Recent Payments</h2>
        <div class="bg-white shadow rounded-lg overflow-hidden">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Reference
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  User
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Payment Type
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Amount
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Status
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Date
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <tr :for={payment <- @recent_payments}>
                <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                  <%= payment.reference_id %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  <div class="flex flex-col">
                    <span class="font-medium text-gray-900">
                      <%= get_user_display_name(payment.user) %>
                    </span>
                    <span class="text-xs text-gray-500">
                      <%= if payment.user, do: payment.user.email, else: "System Transaction" %>
                    </span>
                  </div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  <div class="flex flex-col">
                    <span class={"font-medium #{get_payment_type_color(payment.payment_type_info.type)}"}>
                      <%= payment.payment_type_info.type %>
                    </span>
                    <span class="text-xs text-gray-500">
                      <%= payment.payment_type_info.details %>
                    </span>
                  </div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  <%= Money.to_string!(payment.amount) %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full #{if payment.status == :completed, do: "bg-green-100 text-green-800", else: "bg-yellow-100 text-yellow-800"}"}>
                    <%= payment.status %>
                  </span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  <%= Calendar.strftime(payment.payment_date, "%Y-%m-%d %H:%M") %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm font-medium">
                  <.button
                    phx-click="show_refund_modal"
                    phx-value-payment_id={payment.id}
                    class="bg-red-600 hover:bg-red-700"
                    disabled={payment.status == :refunded}
                  >
                    Refund
                  </.button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
      <!-- Refund Modal -->
      <.modal :if={@show_refund_modal} id="refund-modal" show>
        <h3 class="text-lg font-medium text-gray-900 mb-4">Process Refund</h3>

        <div class="mb-4">
          <p class="text-sm text-gray-600">
            <strong>Payment:</strong> {@selected_payment.reference_id}
          </p>
          <p class="text-sm text-gray-600">
            <strong>Amount:</strong> {Money.to_string(@selected_payment.amount)}
          </p>
          <p class="text-sm text-gray-600">
            <strong>User:</strong> {@selected_payment.user.email}
          </p>
        </div>

        <.form for={@refund_form} phx-submit="process_refund" phx-change="validate_refund">
          <div class="mb-4">
            <.input
              field={@refund_form[:amount]}
              type="text"
              label="Refund Amount"
              placeholder="e.g., 25.00"
              required
            />
          </div>

          <div class="mb-4">
            <.input
              field={@refund_form[:reason]}
              type="textarea"
              label="Reason for Refund"
              placeholder="Enter reason for refund..."
              required
            />
          </div>

          <div class="flex justify-end gap-2">
            <.button
              type="button"
              phx-click="close_refund_modal"
              class="bg-gray-500 hover:bg-gray-600"
            >
              Cancel
            </.button>
            <.button type="submit" class="bg-red-600 hover:bg-red-700">
              Process Refund
            </.button>
          </div>
        </.form>
      </.modal>
      <!-- Credit Modal -->
      <.modal :if={@show_credit_modal} id="credit-modal" show>
        <h3 class="text-lg font-medium text-gray-900 mb-4">Add Credit</h3>

        <div :if={@selected_user} class="mb-4">
          <p class="text-sm text-gray-600">
            <strong>User:</strong> {@selected_user.email}
          </p>
        </div>

        <.form for={@credit_form} phx-submit="process_credit" phx-change="validate_credit">
          <div :if={!@selected_user} class="mb-4">
            <.input
              field={@credit_form[:user_id]}
              type="text"
              label="User ID"
              placeholder="Enter user ID"
              required
            />
          </div>

          <div class="mb-4">
            <.input
              field={@credit_form[:amount]}
              type="text"
              label="Credit Amount"
              placeholder="e.g., 50.00"
              required
            />
          </div>

          <div class="mb-4">
            <.input
              field={@credit_form[:reason]}
              type="textarea"
              label="Reason for Credit"
              placeholder="Enter reason for credit..."
              required
            />
          </div>

          <div class="mb-4">
            <.input
              field={@credit_form[:entity_type]}
              type="select"
              label="Entity Type"
              options={[
                {"Administration", "administration"},
                {"Event", "event"},
                {"Membership", "membership"},
                {"Booking", "booking"},
                {"Donation", "donation"}
              ]}
            />
          </div>

          <div class="mb-4">
            <.input
              field={@credit_form[:entity_id]}
              type="text"
              label="Entity ID (Optional)"
              placeholder="Enter entity ID if applicable"
            />
          </div>

          <div class="flex justify-end gap-2">
            <.button
              type="button"
              phx-click="close_credit_modal"
              class="bg-gray-500 hover:bg-gray-600"
            >
              Cancel
            </.button>
            <.button type="submit" class="bg-green-600 hover:bg-green-700">
              Add Credit
            </.button>
          </div>
        </.form>
      </.modal>
    </.side_menu>
    """
  end

  # Helper functions
  defp parse_date_to_datetime(date_string, time) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> DateTime.new!(date, time)
      {:error, _} -> DateTime.utc_now()
    end
  end

  defp get_payment_type_color(payment_type) do
    case payment_type do
      "Membership" -> "text-blue-600"
      "Event" -> "text-green-600"
      "Booking" -> "text-purple-600"
      "Donation" -> "text-orange-600"
      "Administration" -> "text-gray-600"
      _ -> "text-gray-900"
    end
  end

  defp get_user_display_name(nil), do: "System"

  defp get_user_display_name(user) do
    case {user.first_name, user.last_name} do
      {nil, nil} ->
        "Unknown User"

      {first_name, nil} when is_binary(first_name) ->
        first_name

      {nil, last_name} when is_binary(last_name) ->
        last_name

      {first_name, last_name} when is_binary(first_name) and is_binary(last_name) ->
        "#{first_name} #{last_name}"

      _ ->
        "Unknown User"
    end
  end

  defp refund_changeset(_attrs, params) do
    types = %{
      amount: :string,
      reason: :string
    }

    {%{}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:amount, :reason])
    |> Ecto.Changeset.validate_length(:reason, min: 1, max: 1000)
    |> validate_amount()
  end

  defp credit_changeset(_attrs, params) do
    types = %{
      user_id: :string,
      amount: :string,
      reason: :string,
      entity_type: :string,
      entity_id: :string
    }

    {%{}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:amount, :reason])
    |> Ecto.Changeset.validate_length(:reason, min: 1, max: 1000)
    |> validate_amount()
  end

  defp validate_amount(changeset) do
    case Ecto.Changeset.get_field(changeset, :amount) do
      nil ->
        changeset

      amount_str ->
        case Money.parse(amount_str) do
          {:ok, money} ->
            if Money.positive?(money) do
              changeset
            else
              Ecto.Changeset.add_error(changeset, :amount, "must be positive")
            end

          {:error, _} ->
            Ecto.Changeset.add_error(changeset, :amount, "invalid amount format")
        end
    end
  end
end
