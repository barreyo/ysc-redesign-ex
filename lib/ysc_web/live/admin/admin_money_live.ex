defmodule YscWeb.AdminMoneyLive do
  use YscWeb, :live_view

  alias Ysc.Ledgers
  alias Ysc.Accounts

  @impl true
  def mount(_params, _session, socket) do
    accounts_with_balances = Ledgers.get_accounts_with_balances()

    {:ok,
     socket
     |> assign(:page_title, "Money")
     |> assign(:active_page, :money)
     |> assign(:accounts_with_balances, accounts_with_balances)
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
        {:noreply,
         socket
         |> put_flash(:info, "Refund processed successfully")
         |> assign(:show_refund_modal, false)
         |> assign(:selected_payment, nil)
         |> assign(:accounts_with_balances, Ledgers.get_accounts_with_balances())}

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
        {:noreply,
         socket
         |> put_flash(:info, "Credit added successfully")
         |> assign(:show_credit_modal, false)
         |> assign(:selected_user, nil)
         |> assign(:accounts_with_balances, Ledgers.get_accounts_with_balances())}

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
              <tr :for={payment <- get_recent_payments()}>
                <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                  <%= payment.reference_id %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  <%= payment.user.email %>
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
  defp get_recent_payments do
    import Ecto.Query

    from(p in Ysc.Ledgers.Payment,
      preload: [:user],
      order_by: [desc: p.inserted_at],
      limit: 50
    )
    |> Ysc.Repo.all()
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
