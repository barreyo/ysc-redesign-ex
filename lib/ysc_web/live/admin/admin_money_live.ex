defmodule YscWeb.AdminMoneyLive do
  use YscWeb, :live_view

  alias Ysc.Ledgers
  alias Ysc.Accounts
  alias Ysc.Webhooks
  alias Ysc.Bookings.BookingLocker
  alias Ysc.Tickets
  alias Ysc.Repo
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    # Set default date range to current calendar year
    current_year = DateTime.utc_now().year
    start_date = DateTime.new!(Date.new!(current_year, 1, 1), ~T[00:00:00])
    end_date = DateTime.new!(Date.new!(current_year, 12, 31), ~T[23:59:59])

    accounts_with_balances = Ledgers.get_accounts_with_balances(start_date, end_date)
    recent_payments = Ledgers.get_recent_payments(start_date, end_date)
    ledger_entries = Ledgers.get_ledger_entries(start_date, end_date)

    webhook_events =
      Webhooks.list_webhook_events(
        provider: "stripe",
        start_date: start_date,
        end_date: end_date,
        limit: 100
      )

    {:ok,
     socket
     |> assign(:page_title, "Money")
     |> assign(:active_page, :money)
     |> assign(:accounts_with_balances, accounts_with_balances)
     |> assign(:recent_payments, recent_payments)
     |> assign(:ledger_entries, ledger_entries)
     |> assign(:webhook_events, webhook_events)
     |> assign(:start_date, start_date)
     |> assign(:end_date, end_date)
     |> assign(:show_refund_modal, false)
     |> assign(:show_credit_modal, false)
     |> assign(:show_webhook_modal, false)
     |> assign(:selected_payment, nil)
     |> assign(:selected_user, nil)
     |> assign(:selected_webhook, nil)
     |> assign(:selected_entry, nil)
     |> assign(:ticket_order, nil)
     |> assign(:refund_form, to_form(%{}, as: :refund))
     |> assign(:credit_form, to_form(%{}, as: :credit))
     |> assign(:entry_form, to_form(%{}, as: :entry))
     |> assign(:show_entry_modal, false)
     |> assign(:ledger_accounts, Ledgers.list_accounts())
     |> assign(:sections_collapsed, %{
       accounts: false,
       quick_actions: false,
       payments: false,
       ledger_entries: true,
       webhooks: true
     })}
  end

  @impl true
  def handle_event("show_refund_modal", %{"payment_id" => payment_id}, socket) do
    payment = Ledgers.get_payment_with_associations(payment_id)

    # Check if this payment is for a ticket order
    ticket_order =
      from(e in Ysc.Ledgers.LedgerEntry,
        where: e.payment_id == ^payment_id,
        where: e.related_entity_type == :event,
        limit: 1
      )
      |> Repo.one()
      |> case do
        nil ->
          nil

        _entry ->
          Tickets.get_ticket_order_by_payment_id(payment_id)
      end

    # Initialize refund form with ticket selection fields
    refund_form =
      if ticket_order do
        # For ticket orders, include ticket_ids field
        {%{},
         %{
           amount: :string,
           reason: :string,
           release_availability: :boolean,
           ticket_ids: {:array, :string}
         }}
        |> Ecto.Changeset.cast(%{}, [:amount, :reason, :release_availability, :ticket_ids])
        |> to_form(as: :refund)
      else
        {%{}, %{amount: :string, reason: :string, release_availability: :boolean}}
        |> Ecto.Changeset.cast(%{}, [:amount, :reason, :release_availability])
        |> to_form(as: :refund)
      end

    {:noreply,
     socket
     |> assign(:show_refund_modal, true)
     |> assign(:selected_payment, payment)
     |> assign(:ticket_order, ticket_order)
     |> assign(:refund_form, refund_form)}
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
     |> assign(:selected_payment, nil)
     |> assign(:ticket_order, nil)}
  end

  @impl true
  def handle_event("close_credit_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_credit_modal, false)
     |> assign(:selected_user, nil)}
  end

  @impl true
  def handle_event("show_webhook_modal", %{"webhook_id" => webhook_id}, socket) do
    webhook = Webhooks.get_webhook_event(webhook_id)

    {:noreply,
     socket
     |> assign(:show_webhook_modal, true)
     |> assign(:selected_webhook, webhook)}
  end

  @impl true
  def handle_event("close_webhook_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_webhook_modal, false)
     |> assign(:selected_webhook, nil)}
  end

  @impl true
  def handle_event("show_entry_modal", %{"entry_id" => entry_id}, socket) do
    entry = Ledgers.get_entry(entry_id)

    entry_changeset =
      %{
        account_id: entry.account_id,
        amount: Money.to_string!(entry.amount),
        description: entry.description,
        debit_credit: entry.debit_credit
      }
      |> entry_changeset()

    {:noreply,
     socket
     |> assign(:show_entry_modal, true)
     |> assign(:selected_entry, entry)
     |> assign(:entry_form, to_form(entry_changeset, as: :entry))}
  end

  @impl true
  def handle_event("close_entry_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_entry_modal, false)
     |> assign(:selected_entry, nil)
     |> assign(:entry_form, to_form(%{}, as: :entry))}
  end

  @impl true
  def handle_event("validate_entry", %{"entry" => entry_params}, socket) do
    changeset = entry_params |> entry_changeset() |> Map.put(:action, :validate)

    {:noreply, assign(socket, :entry_form, to_form(changeset, as: :entry))}
  end

  @impl true
  def handle_event("update_entry", %{"entry" => entry_params}, socket) do
    %{selected_entry: entry} = socket.assigns

    # Parse amount
    case parse_amount_string(entry_params["amount"]) do
      {:ok, amount} ->
        attrs = %{
          account_id: entry_params["account_id"],
          amount: amount,
          description: entry_params["description"],
          debit_credit: entry_params["debit_credit"]
        }

        case Ledgers.update_entry_with_balance(entry.id, attrs) do
          {:ok, _updated_entry} ->
            # Refresh data
            %{start_date: start_date, end_date: end_date} = socket.assigns
            ledger_entries = Ledgers.get_ledger_entries(start_date, end_date)

            {:noreply,
             socket
             |> put_flash(
               :info,
               "Ledger entry updated successfully (corresponding entry also updated)"
             )
             |> assign(:show_entry_modal, false)
             |> assign(:selected_entry, nil)
             |> assign(:ledger_entries, ledger_entries)
             |> assign(:entry_form, to_form(%{}, as: :entry))}

          {:error, reason} ->
            error_message =
              case reason do
                {:error, changeset} when is_map(changeset) ->
                  "Validation errors: #{inspect(changeset.errors)}"

                {:error, :not_found} ->
                  "Entry not found"

                {:error, {:corresponding_entry_update_failed, changeset}} ->
                  "Failed to update corresponding entry: #{inspect(changeset.errors)}"

                _ ->
                  "Failed to update entry: #{inspect(reason)}"
              end

            {:noreply,
             socket
             |> put_flash(:error, error_message)}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Invalid amount format")}
    end
  end

  @impl true
  def handle_event("process_refund", %{"refund" => refund_params}, socket) do
    %{selected_payment: payment, ticket_order: ticket_order} = socket.assigns

    # Check if this is a partial ticket refund
    ticket_ids = if refund_params["ticket_ids"], do: refund_params["ticket_ids"], else: []

    # If ticket IDs are provided, refund individual tickets
    if ticket_order && length(ticket_ids) > 0 do
      case Tickets.refund_tickets(ticket_order, ticket_ids, refund_params["reason"]) do
        {:ok, %{refund_amount: calculated_refund_amount}} ->
          # Process the ledger refund with the calculated amount
          refund_attrs = %{
            payment_id: payment.id,
            refund_amount: calculated_refund_amount,
            reason: refund_params["reason"],
            external_refund_id: "admin_refund_#{Ecto.ULID.generate()}"
          }

          case Ledgers.process_refund(refund_attrs) do
            {:ok, {_refund, _transaction, _entries}} ->
              # Refresh data
              %{start_date: start_date, end_date: end_date} = socket.assigns
              accounts_with_balances = Ledgers.get_accounts_with_balances(start_date, end_date)
              recent_payments = Ledgers.get_recent_payments(start_date, end_date)
              ledger_entries = Ledgers.get_ledger_entries(start_date, end_date)

              webhook_events =
                Webhooks.list_webhook_events(
                  provider: "stripe",
                  start_date: start_date,
                  end_date: end_date,
                  limit: 100
                )

              {:noreply,
               socket
               |> put_flash(
                 :info,
                 "Refunded #{length(ticket_ids)} ticket(s) successfully. Amount: #{Money.to_string!(calculated_refund_amount)}"
               )
               |> assign(:show_refund_modal, false)
               |> assign(:selected_payment, nil)
               |> assign(:ticket_order, nil)
               |> assign(:accounts_with_balances, accounts_with_balances)
               |> assign(:recent_payments, recent_payments)
               |> assign(:ledger_entries, ledger_entries)
               |> assign(:webhook_events, webhook_events)}

            {:error, _changeset} ->
              {:noreply,
               socket
               |> put_flash(:error, "Failed to process refund in ledger")}
          end

        {:error, reason} ->
          {:noreply,
           socket
           |> put_flash(:error, "Failed to refund tickets: #{inspect(reason)}")}
      end
    else
      # Full refund (existing logic)
      case parse_amount_string(refund_params["amount"]) do
        {:ok, refund_amount} ->
          refund_attrs = %{
            payment_id: payment.id,
            refund_amount: refund_amount,
            reason: refund_params["reason"],
            external_refund_id: "admin_refund_#{Ecto.ULID.generate()}"
          }

          # Check if we should release availability
          release_availability = refund_params["release_availability"] == "true"

          case Ledgers.process_refund(refund_attrs) do
            {:ok, {_refund, _transaction, _entries}} ->
              # If checkbox is checked, cancel booking or ticket order to release availability
              release_result =
                if release_availability do
                  release_availability_for_payment(payment.id)
                else
                  :ok
                end

              # Refresh data with current date range
              %{start_date: start_date, end_date: end_date} = socket.assigns
              accounts_with_balances = Ledgers.get_accounts_with_balances(start_date, end_date)
              recent_payments = Ledgers.get_recent_payments(start_date, end_date)
              ledger_entries = Ledgers.get_ledger_entries(start_date, end_date)

              webhook_events =
                Webhooks.list_webhook_events(
                  provider: "stripe",
                  start_date: start_date,
                  end_date: end_date,
                  limit: 100
                )

              flash_message =
                case release_result do
                  {:ok, :booking_refunded} ->
                    "Refund processed successfully and booking marked as refunded (dates released)"

                  {:ok, :ticket_order_canceled} ->
                    "Refund processed successfully and tickets released"

                  {:ok, :not_found} ->
                    "Refund processed successfully (no booking or ticket order found to release)"

                  {:error, reason} ->
                    require Logger

                    Logger.warning("Refund processed but failed to release availability",
                      payment_id: payment.id,
                      reason: reason
                    )

                    "Refund processed successfully (warning: failed to release availability)"

                  _ ->
                    "Refund processed successfully"
                end

              {:noreply,
               socket
               |> put_flash(:info, flash_message)
               |> assign(:show_refund_modal, false)
               |> assign(:selected_payment, nil)
               |> assign(:ticket_order, nil)
               |> assign(:accounts_with_balances, accounts_with_balances)
               |> assign(:recent_payments, recent_payments)
               |> assign(:ledger_entries, ledger_entries)
               |> assign(:webhook_events, webhook_events)}

            {:error, _changeset} ->
              {:noreply,
               socket
               |> put_flash(:error, "Failed to process refund")}
          end

        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(:error, "Invalid amount format")}
      end
    end
  end

  @impl true
  def handle_event("process_credit", %{"credit" => credit_params}, socket) do
    %{selected_user: user} = socket.assigns

    case parse_amount_string(credit_params["amount"]) do
      {:ok, amount} ->
        credit_attrs = %{
          user_id: user.id,
          amount: amount,
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
            ledger_entries = Ledgers.get_ledger_entries(start_date, end_date)

            webhook_events =
              Webhooks.list_webhook_events(
                provider: "stripe",
                start_date: start_date,
                end_date: end_date,
                limit: 100
              )

            {:noreply,
             socket
             |> put_flash(:info, "Credit added successfully")
             |> assign(:show_credit_modal, false)
             |> assign(:selected_user, nil)
             |> assign(:accounts_with_balances, accounts_with_balances)
             |> assign(:recent_payments, recent_payments)
             |> assign(:ledger_entries, ledger_entries)
             |> assign(:webhook_events, webhook_events)}

          {:error, _changeset} ->
            {:noreply,
             socket
             |> put_flash(:error, "Failed to add credit")}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Invalid amount format")}
    end
  end

  @impl true
  def handle_event("validate_refund", %{"refund" => refund_params}, socket) do
    %{ticket_order: ticket_order} = socket.assigns

    # For ticket orders, ensure ticket_ids are always present in refund_params
    # When checkboxes are clicked, only checked ones are sent in the form params
    # So we use the params directly (they contain all currently checked boxes)
    refund_params =
      if ticket_order do
        # Use ticket_ids from params if present, otherwise use empty list
        ticket_ids = refund_params["ticket_ids"] || []
        Map.put(refund_params, "ticket_ids", ticket_ids)
      else
        refund_params
      end

    # If this is a ticket order and tickets are selected, calculate the refund amount
    refund_params =
      if ticket_order && refund_params["ticket_ids"] && length(refund_params["ticket_ids"]) > 0 do
        # Convert ticket_ids from strings to proper format for comparison
        ticket_ids = refund_params["ticket_ids"]

        # Calculate refund amount based on selected tickets
        refund_amount =
          ticket_order.tickets
          |> Enum.filter(fn ticket -> to_string(ticket.id) in ticket_ids end)
          |> Enum.filter(&(&1.status in [:confirmed, :pending]))
          |> Enum.reduce(Money.new(0, :USD), fn ticket, acc ->
            case ticket.ticket_tier.type do
              :free ->
                acc

              :donation ->
                # For donation tickets, calculate proportionally
                if ticket_order.total_amount do
                  donation_tickets_count =
                    ticket_order.tickets
                    |> Enum.filter(fn t ->
                      t.ticket_tier.type == :donation && t.status in [:confirmed, :pending]
                    end)
                    |> length()

                  if donation_tickets_count > 0 do
                    case Money.div(ticket_order.total_amount, donation_tickets_count) do
                      {:ok, ticket_amount} ->
                        case Money.add(acc, ticket_amount) do
                          {:ok, new_total} -> new_total
                          {:error, _} -> acc
                        end

                      {:error, _} ->
                        acc
                    end
                  else
                    acc
                  end
                else
                  acc
                end

              _ ->
                # For paid tickets, use the tier price
                if ticket.ticket_tier.price do
                  case Money.add(acc, ticket.ticket_tier.price) do
                    {:ok, new_total} -> new_total
                    {:error, _} -> acc
                  end
                else
                  acc
                end
            end
          end)

        # Update the amount in refund_params with the calculated value
        Map.put(refund_params, "amount", Money.to_string!(refund_amount))
      else
        # If no tickets selected and this is a ticket order, clear the amount
        if ticket_order do
          Map.put(refund_params, "amount", "")
        else
          refund_params
        end
      end

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
  def handle_event("toggle_section", %{"section" => section}, socket) do
    section_atom = String.to_existing_atom(section)
    current_state = socket.assigns.sections_collapsed[section_atom]

    updated_sections =
      Map.update!(socket.assigns.sections_collapsed, section_atom, fn _ -> !current_state end)

    {:noreply, assign(socket, :sections_collapsed, updated_sections)}
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
    ledger_entries = Ledgers.get_ledger_entries(start_date, end_date)

    webhook_events =
      Webhooks.list_webhook_events(
        provider: "stripe",
        start_date: start_date,
        end_date: end_date,
        limit: 100
      )

    {:noreply,
     socket
     |> assign(:accounts_with_balances, accounts_with_balances)
     |> assign(:recent_payments, recent_payments)
     |> assign(:ledger_entries, ledger_entries)
     |> assign(:webhook_events, webhook_events)
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
      <div class="mb-6 bg-white p-4 rounded border">
        <h3 class="text-lg font-medium text-zinc-900 mb-4">Date Range Filter</h3>
        <form phx-submit="update_date_range" class="flex gap-4 items-end">
          <div>
            <label for="start_date" class="block text-sm font-medium text-zinc-700 mb-1">
              Start Date
            </label>
            <input
              type="date"
              id="start_date"
              name="start_date"
              value={Calendar.strftime(@start_date, "%Y-%m-%d")}
              class="block w-full rounded-md border-zinc-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
            />
          </div>
          <div>
            <label for="end_date" class="block text-sm font-medium text-zinc-700 mb-1">
              End Date
            </label>
            <input
              type="date"
              id="end_date"
              name="end_date"
              value={Calendar.strftime(@end_date, "%Y-%m-%d")}
              class="block w-full rounded-md border-zinc-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
            />
          </div>
          <.button type="submit" class="bg-blue-600 hover:bg-blue-700">
            Update
          </.button>
        </form>
        <p class="text-sm text-zinc-600 mt-2">
          Showing data from <%= Calendar.strftime(@start_date, "%B %d, %Y") %> to <%= Calendar.strftime(
            @end_date,
            "%B %d, %Y"
          ) %>
        </p>
      </div>
      <!-- Account Balances -->
      <div class="mb-8 bg-white rounded border">
        <button
          phx-click="toggle_section"
          phx-value-section="accounts"
          class="w-full flex items-center justify-between p-4 text-left hover:bg-zinc-50 transition-colors"
        >
          <h2 class="text-xl font-semibold text-zinc-800">Account Balances</h2>
          <.icon
            name={
              if @sections_collapsed.accounts, do: "hero-chevron-right", else: "hero-chevron-down"
            }
            class="w-5 h-5 text-zinc-600"
          />
        </button>
        <div :if={!@sections_collapsed.accounts} class="p-4 pt-0">
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            <div :for={account_data <- @accounts_with_balances} class="bg-white p-4 rounded border">
              <div class="flex justify-between items-start mb-2">
                <h3 class="font-medium text-zinc-900"><%= account_data.account.name %></h3>
                <span class={"px-2 py-1 text-xs font-semibold rounded #{get_normal_balance_badge_color(account_data.account.normal_balance)}"}>
                  <%= String.capitalize(to_string(account_data.account.normal_balance || "debit")) %>-normal
                </span>
              </div>
              <p class="text-sm text-zinc-600 mb-2"><%= account_data.account.description %></p>
              <p class={"text-lg font-semibold mt-2 #{get_balance_color(account_data.balance, account_data.account.normal_balance)}"}>
                <%= Money.to_string!(account_data.balance || Money.new(0, :USD)) %>
              </p>
              <p class="text-xs text-zinc-500 capitalize mt-1">
                <%= account_data.account.account_type %>
              </p>
            </div>
          </div>
        </div>
      </div>
      <!-- Recent Payments -->
      <div class="mb-8 bg-white rounded border">
        <button
          phx-click="toggle_section"
          phx-value-section="payments"
          class="w-full flex items-center justify-between p-4 text-left hover:bg-zinc-50 transition-colors"
        >
          <h2 class="text-xl font-semibold text-zinc-800">Recent Payments</h2>
          <.icon
            name={
              if @sections_collapsed.payments, do: "hero-chevron-right", else: "hero-chevron-down"
            }
            class="w-5 h-5 text-zinc-600"
          />
        </button>
        <div :if={!@sections_collapsed.payments} class="overflow-hidden">
          <table class="min-w-full divide-y divide-zinc-200">
            <thead class="bg-zinc-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Reference
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  User
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Payment Type
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Amount
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Status
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Date
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-zinc-200">
              <tr :for={payment <- @recent_payments}>
                <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-zinc-900">
                  <%= payment.reference_id %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                  <div class="flex flex-col">
                    <span class="font-medium text-zinc-900">
                      <%= get_user_display_name(payment.user) %>
                    </span>
                    <span class="text-xs text-zinc-500">
                      <%= if payment.user, do: payment.user.email, else: "System Transaction" %>
                    </span>
                  </div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                  <div class="flex flex-col">
                    <span class={"font-medium #{get_payment_type_color(payment.payment_type_info.type)}"}>
                      <%= payment.payment_type_info.type %>
                    </span>
                    <span class="text-xs text-zinc-500">
                      <%= payment.payment_type_info.details %>
                    </span>
                  </div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                  <%= Money.to_string!(payment.amount) %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full #{if payment.status == :completed, do: "bg-green-100 text-green-800", else: "bg-yellow-100 text-yellow-800"}"}>
                    <%= payment.status %>
                  </span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                  <%= Calendar.strftime(payment.payment_date, "%Y-%m-%d %H:%M") %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm font-medium">
                  <.button
                    :if={payment.payment_type_info.type != "Payout"}
                    phx-click="show_refund_modal"
                    phx-value-payment_id={payment.id}
                    class="bg-red-600 hover:bg-red-700"
                    disabled={payment.status == :refunded}
                  >
                    Refund
                  </.button>
                  <span
                    :if={payment.payment_type_info.type == "Payout"}
                    class="text-sm text-zinc-400 italic"
                  >
                    N/A
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
      <!-- Ledger Entries -->
      <div class="mb-8 rounded border">
        <button
          phx-click="toggle_section"
          phx-value-section="ledger_entries"
          class="w-full flex items-center justify-between p-4 text-left hover:bg-zinc-50 transition-colors"
        >
          <h2 class="text-xl font-semibold text-zinc-800">Ledger Entries</h2>
          <.icon
            name={
              if @sections_collapsed.ledger_entries,
                do: "hero-chevron-right",
                else: "hero-chevron-down"
            }
            class="w-5 h-5 text-zinc-600"
          />
        </button>
        <div :if={!@sections_collapsed.ledger_entries} class="overflow-hidden">
          <table class="min-w-full divide-y divide-zinc-200">
            <thead class="bg-zinc-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Date
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Account
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Description
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Debit/Credit
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Amount
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Payment
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Entity
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-zinc-200">
              <tr :for={entry <- @ledger_entries}>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                  <%= Calendar.strftime(entry.inserted_at, "%Y-%m-%d %H:%M") %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                  <div class="flex flex-col">
                    <span class="font-medium text-zinc-900">
                      <%= entry.account.name %>
                    </span>
                    <span class="text-xs text-zinc-500">
                      <%= String.capitalize(to_string(entry.account.account_type)) %>
                    </span>
                  </div>
                </td>
                <td class="px-6 py-4 text-sm text-zinc-900 max-w-xs">
                  <div class="truncate" title={entry.description}>
                    <%= entry.description %>
                  </div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full #{get_debit_credit_badge_color(entry.debit_credit)}"}>
                    <%= String.capitalize(to_string(entry.debit_credit)) %>
                  </span>
                </td>
                <td class={"px-6 py-4 whitespace-nowrap text-sm font-medium #{get_debit_credit_amount_color(entry.debit_credit)}"}>
                  <%= Money.to_string!(entry.amount) %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-600">
                  <%= if entry.payment do %>
                    <span class="font-mono text-xs">
                      <%= entry.payment.reference_id %>
                    </span>
                  <% else %>
                    <span class="text-zinc-400">—</span>
                  <% end %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-600">
                  <%= if entry.related_entity_type do %>
                    <div class="flex flex-col">
                      <span class="text-xs font-medium text-zinc-700">
                        <%= String.capitalize(to_string(entry.related_entity_type)) %>
                      </span>
                      <%= if entry.related_entity_id do %>
                        <span class="text-xs font-mono text-zinc-500">
                          <%= String.slice(to_string(entry.related_entity_id), 0..8) %>...
                        </span>
                      <% end %>
                    </div>
                  <% else %>
                    <span class="text-zinc-400">—</span>
                  <% end %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm font-medium">
                  <.button
                    phx-click="show_entry_modal"
                    phx-value-entry_id={entry.id}
                    class="bg-yellow-600 hover:bg-yellow-700 text-xs"
                  >
                    Edit
                  </.button>
                </td>
              </tr>
              <tr :if={Enum.empty?(@ledger_entries)}>
                <td colspan="8" class="px-6 py-4 text-center text-sm text-zinc-500">
                  No ledger entries found for the selected date range.
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
      <!-- Stripe Webhooks -->
      <div class="mb-8 rounded border">
        <button
          phx-click="toggle_section"
          phx-value-section="webhooks"
          class="w-full flex items-center justify-between p-4 text-left hover:bg-zinc-50 transition-colors"
        >
          <h2 class="text-xl font-semibold text-zinc-800">Stripe Webhook Events</h2>
          <.icon
            name={
              if @sections_collapsed.webhooks, do: "hero-chevron-right", else: "hero-chevron-down"
            }
            class="w-5 h-5 text-zinc-600"
          />
        </button>
        <div :if={!@sections_collapsed.webhooks} class="overflow-hidden">
          <table class="min-w-full divide-y divide-zinc-200">
            <thead class="bg-zinc-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Event ID
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Event Type
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  State
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Received At
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-zinc-200">
              <tr :for={webhook <- @webhook_events}>
                <td class="px-6 py-4 whitespace-nowrap text-sm font-mono text-zinc-900">
                  <%= String.slice(webhook.event_id, 0..20) %>...
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                  <span class="font-medium"><%= webhook.event_type %></span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full #{get_webhook_state_color(webhook.state)}"}>
                    <%= webhook.state %>
                  </span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                  <%= Calendar.strftime(webhook.inserted_at, "%Y-%m-%d %H:%M:%S") %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm font-medium">
                  <.button
                    phx-click="show_webhook_modal"
                    phx-value-webhook_id={webhook.id}
                    class="bg-blue-600 hover:bg-blue-700"
                  >
                    View Details
                  </.button>
                </td>
              </tr>
              <tr :if={Enum.empty?(@webhook_events)}>
                <td colspan="5" class="px-6 py-4 text-center text-sm text-zinc-500">
                  No webhook events found for the selected date range.
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
      <!-- Refund Modal -->
      <.modal :if={@show_refund_modal} id="refund-modal" show>
        <h3 class="text-lg font-medium text-zinc-900 mb-4">Process Refund</h3>

        <div class="mb-4">
          <p class="text-sm text-zinc-600">
            <strong>Payment:</strong> <%= @selected_payment.reference_id %>
          </p>
          <p class="text-sm text-zinc-600">
            <strong>Amount:</strong> <%= Money.to_string!(@selected_payment.amount) %>
          </p>
          <p :if={@selected_payment.user} class="text-sm text-zinc-600">
            <strong>User:</strong> <%= @selected_payment.user.email %>
          </p>
        </div>

        <.form for={@refund_form} phx-submit="process_refund" phx-change="validate_refund">
          <!-- Ticket Selection for Ticket Orders -->
          <div :if={@ticket_order} class="mb-4 p-4 bg-blue-50 rounded border border-blue-200">
            <h4 class="text-sm font-semibold text-zinc-800 mb-3">
              Select Tickets to Refund
            </h4>
            <p class="text-xs text-zinc-600 mb-3">
              Only selected tickets will be refunded and returned to stock.
            </p>
            <div class="space-y-2 max-h-64 overflow-y-auto">
              <label
                :for={
                  ticket <-
                    (@ticket_order.tickets || [])
                    |> Enum.filter(&(&1.status in [:confirmed, :pending]))
                }
                class="flex items-start p-2 border border-zinc-200 rounded hover:bg-blue-100 cursor-pointer"
              >
                <input
                  type="checkbox"
                  name="refund[ticket_ids][]"
                  value={ticket.id}
                  class="mt-1 mr-3"
                  checked={
                    ticket_id_str = to_string(ticket.id)
                    # Get ticket_ids from changeset changes first, then from params, then from data
                    ticket_ids =
                      case Ecto.Changeset.get_change(@refund_form.source, :ticket_ids) do
                        nil ->
                          # Try to get from params (for form state)
                          case @refund_form.source.params do
                            %{"ticket_ids" => ids} when is_list(ids) ->
                              ids

                            _ ->
                              # Fall back to data
                              case Ecto.Changeset.get_field(@refund_form.source, :ticket_ids) do
                                nil -> []
                                ids when is_list(ids) -> ids
                                _ -> []
                              end
                          end

                        ids when is_list(ids) ->
                          ids

                        _ ->
                          []
                      end

                    ticket_id_str in Enum.map(ticket_ids, &to_string/1)
                  }
                />
                <div class="flex-1">
                  <div class="text-sm font-medium text-zinc-900">
                    <%= ticket.ticket_tier.name %>
                  </div>
                  <div class="text-xs text-zinc-600">
                    Ticket ID: <%= ticket.reference_id || ticket.id %>
                  </div>
                  <div class="text-xs font-medium text-zinc-700 mt-1">
                    <%= cond do
                      ticket.ticket_tier.type == :free -> "Free"
                      ticket.ticket_tier.type == :donation -> "Donation"
                      true -> Money.to_string!(ticket.ticket_tier.price || Money.new(0, :USD))
                    end %>
                  </div>
                </div>
              </label>
            </div>
            <p
              :if={
                (@ticket_order.tickets || [])
                |> Enum.filter(&(&1.status in [:confirmed, :pending]))
                |> length() == 0
              }
              class="text-sm text-zinc-500 italic"
            >
              No refundable tickets found (all tickets are already cancelled or expired).
            </p>
          </div>
          <div class="mb-4">
            <.input
              field={@refund_form[:amount]}
              type="text"
              label="Refund Amount"
              placeholder="e.g., 25.00"
              required
            />
            <p :if={@ticket_order} class="text-xs text-zinc-500 mt-1">
              Amount will be calculated automatically when you select tickets above.
            </p>
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

          <div class="mb-4">
            <.input
              field={@refund_form[:release_availability]}
              type="checkbox"
              label="Release tickets/booking for others to purchase"
            />
          </div>

          <div class="flex justify-end gap-2">
            <.button
              type="button"
              phx-click="close_refund_modal"
              class="bg-zinc-500 hover:bg-zinc-600"
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
        <h3 class="text-lg font-medium text-zinc-900 mb-4">Add Credit</h3>

        <div :if={@selected_user} class="mb-4">
          <p class="text-sm text-zinc-600">
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
              class="bg-zinc-500 hover:bg-zinc-600"
            >
              Cancel
            </.button>
            <.button type="submit" class="bg-green-600 hover:bg-green-700">
              Add Credit
            </.button>
          </div>
        </.form>
      </.modal>
      <!-- Webhook Details Modal -->
      <.modal :if={@show_webhook_modal && @selected_webhook} id="webhook-modal" show>
        <h3 class="text-lg font-medium text-zinc-900 mb-4">Webhook Event Details</h3>

        <div class="mb-4 space-y-2">
          <div>
            <p class="text-sm">
              <strong class="text-zinc-900">Event ID:</strong>
              <span class="text-zinc-600 font-mono text-xs ml-2">
                <%= @selected_webhook.event_id %>
              </span>
            </p>
          </div>
          <div>
            <p class="text-sm">
              <strong class="text-zinc-900">Event Type:</strong>
              <span class="text-zinc-600 ml-2"><%= @selected_webhook.event_type %></span>
            </p>
          </div>
          <div>
            <p class="text-sm">
              <strong class="text-zinc-900">Provider:</strong>
              <span class="text-zinc-600 ml-2 capitalize"><%= @selected_webhook.provider %></span>
            </p>
          </div>
          <div>
            <p class="text-sm">
              <strong class="text-zinc-900">State:</strong>
              <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full ml-2 #{get_webhook_state_color(@selected_webhook.state)}"}>
                <%= @selected_webhook.state %>
              </span>
            </p>
          </div>
          <div>
            <p class="text-sm">
              <strong class="text-zinc-900">Received At:</strong>
              <span class="text-zinc-600 ml-2">
                <%= Calendar.strftime(@selected_webhook.inserted_at, "%Y-%m-%d %H:%M:%S UTC") %>
              </span>
            </p>
          </div>
          <div>
            <p class="text-sm">
              <strong class="text-zinc-900">Last Updated:</strong>
              <span class="text-zinc-600 ml-2">
                <%= Calendar.strftime(@selected_webhook.updated_at, "%Y-%m-%d %H:%M:%S UTC") %>
              </span>
            </p>
          </div>
        </div>

        <div class="mb-4">
          <label class="block text-sm font-medium text-zinc-900 mb-2">Payload</label>
          <pre class="bg-zinc-50 border border-zinc-200 rounded p-4 text-xs overflow-auto max-h-96 font-mono text-zinc-800"><%= Jason.encode!(@selected_webhook.payload, pretty: true) %></pre>
        </div>

        <div class="flex justify-end gap-2">
          <.button type="button" phx-click="close_webhook_modal" class="bg-zinc-500 hover:bg-zinc-600">
            Close
          </.button>
        </div>
      </.modal>
      <!-- Edit Ledger Entry Modal -->
      <.modal :if={@show_entry_modal && @selected_entry} id="entry-modal" show>
        <div class="mb-4">
          <div class="bg-yellow-50 border border-yellow-200 rounded-lg p-3 mb-4">
            <p class="text-sm text-yellow-800 font-semibold">
              ⚠️ Development Tool: Editing ledger entries
            </p>
            <p class="text-xs text-yellow-700 mt-1">
              This will update the corresponding entry to maintain double-entry balance. Use with caution.
            </p>
          </div>
          <h3 class="text-lg font-medium text-zinc-900 mb-4">Edit Ledger Entry</h3>
          <div class="mb-4 space-y-2 text-sm text-zinc-600">
            <p>
              <strong>Entry ID:</strong>
              <span class="font-mono text-xs ml-2">
                <%= String.slice(to_string(@selected_entry.id), 0..12) %>...
              </span>
            </p>
            <p>
              <strong>Payment:</strong>
              <%= if @selected_entry.payment do %>
                <span class="font-mono text-xs ml-2">
                  <%= @selected_entry.payment.reference_id %>
                </span>
              <% else %>
                <span class="text-zinc-400 ml-2">None</span>
              <% end %>
            </p>
            <p>
              <strong>Current Type:</strong>
              <span class="ml-2 capitalize"><%= @selected_entry.debit_credit %></span>
            </p>
          </div>
        </div>

        <.form for={@entry_form} phx-submit="update_entry" phx-change="validate_entry">
          <div class="mb-4">
            <.input
              field={@entry_form[:account_id]}
              type="select"
              label="Account"
              options={Enum.map(@ledger_accounts, fn account -> {account.name, account.id} end)}
              required
            />
          </div>

          <div class="mb-4">
            <.input
              field={@entry_form[:amount]}
              type="text"
              label="Amount"
              placeholder="e.g., 100.00"
              required
            />
          </div>

          <div class="mb-4">
            <.input
              field={@entry_form[:description]}
              type="textarea"
              label="Description"
              placeholder="Enter description..."
              required
            />
          </div>

          <div class="mb-4">
            <.input
              field={@entry_form[:debit_credit]}
              type="select"
              label="Debit/Credit"
              options={[{"Debit", "debit"}, {"Credit", "credit"}]}
              required
            />
          </div>

          <div class="flex justify-end gap-2">
            <.button type="button" phx-click="close_entry_modal" class="bg-zinc-500 hover:bg-zinc-600">
              Cancel
            </.button>
            <.button type="submit" class="bg-yellow-600 hover:bg-yellow-700">
              Update Entry
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
      "Administration" -> "text-zinc-600"
      _ -> "text-zinc-900"
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
    # Include ticket_ids if present (for ticket order refunds)
    base_types = %{
      amount: :string,
      reason: :string,
      release_availability: :boolean
    }

    types =
      if Map.has_key?(params, "ticket_ids") || Map.has_key?(params, :ticket_ids) do
        Map.put(base_types, :ticket_ids, {:array, :string})
      else
        base_types
      end

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
        case parse_amount_string(amount_str) do
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

  defp get_webhook_state_color(state) do
    case state do
      :processed -> "bg-green-100 text-green-800"
      :failed -> "bg-red-100 text-red-800"
      :processing -> "bg-yellow-100 text-yellow-800"
      :pending -> "bg-blue-100 text-blue-800"
      _ -> "bg-zinc-100 text-zinc-800"
    end
  end

  defp get_normal_balance_badge_color("credit"), do: "bg-blue-100 text-blue-800"
  defp get_normal_balance_badge_color("debit"), do: "bg-purple-100 text-purple-800"
  defp get_normal_balance_badge_color(:credit), do: "bg-blue-100 text-blue-800"
  defp get_normal_balance_badge_color(:debit), do: "bg-purple-100 text-purple-800"
  defp get_normal_balance_badge_color(_), do: "bg-zinc-100 text-zinc-800"

  # Determine balance color based on whether it's positive or negative
  # For credit-normal accounts, positive is good (green)
  # For debit-normal accounts, positive is good (green)
  # Negative balances are shown in red for both types
  defp get_balance_color(balance, _normal_balance) when is_nil(balance), do: "text-zinc-600"

  defp get_balance_color(balance, _normal_balance) do
    is_positive = Money.positive?(balance)
    is_zero = Money.equal?(balance, Money.new(0, :USD))

    cond do
      is_zero -> "text-zinc-600"
      is_positive -> "text-green-600"
      true -> "text-red-600"
    end
  end

  defp get_debit_credit_badge_color("debit"), do: "bg-purple-100 text-purple-800"
  defp get_debit_credit_badge_color("credit"), do: "bg-blue-100 text-blue-800"
  defp get_debit_credit_badge_color(:debit), do: "bg-purple-100 text-purple-800"
  defp get_debit_credit_badge_color(:credit), do: "bg-blue-100 text-blue-800"
  defp get_debit_credit_badge_color(_), do: "bg-zinc-100 text-zinc-800"

  defp get_debit_credit_amount_color("debit"), do: "text-purple-700"
  defp get_debit_credit_amount_color("credit"), do: "text-blue-700"
  defp get_debit_credit_amount_color(:debit), do: "text-purple-700"
  defp get_debit_credit_amount_color(:credit), do: "text-blue-700"
  defp get_debit_credit_amount_color(_), do: "text-zinc-900"

  defp entry_changeset(params) do
    types = %{
      account_id: :string,
      amount: :string,
      description: :string,
      debit_credit: :string
    }

    {%{}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:account_id, :amount, :description, :debit_credit])
    |> Ecto.Changeset.validate_length(:description, min: 1, max: 1000)
    |> Ecto.Changeset.validate_inclusion(:debit_credit, ["debit", "credit"])
    |> validate_entry_amount()
  end

  defp validate_entry_amount(changeset) do
    case Ecto.Changeset.get_field(changeset, :amount) do
      nil ->
        changeset

      amount_str ->
        # Use MoneyHelper.parse_money or try Money.new with string
        case parse_amount_string(amount_str) do
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

  defp parse_amount_string(amount_str) when is_binary(amount_str) do
    # Try parsing as decimal first
    case Decimal.parse(String.replace(amount_str, ",", "")) do
      {decimal, _} ->
        try do
          money = Money.new(decimal, :USD)
          {:ok, money}
        rescue
          _ -> {:error, :invalid_format}
        end

      :error ->
        {:error, :invalid_format}
    end
  end

  defp parse_amount_string(_), do: {:error, :invalid_format}

  # Helper function to release availability for a payment (booking or ticket order)
  defp release_availability_for_payment(payment_id) do
    # Find booking associated with this payment
    booking =
      from(e in Ysc.Ledgers.LedgerEntry,
        join: b in Ysc.Bookings.Booking,
        on: e.related_entity_id == b.id,
        where: e.payment_id == ^payment_id,
        where: e.related_entity_type == :booking,
        where: b.status == :complete,
        limit: 1,
        select: b
      )
      |> Repo.one()

    if booking do
      # Mark as refunded and release inventory
      case BookingLocker.refund_complete_booking(booking.id, true) do
        {:ok, _refunded_booking} ->
          require Logger

          Logger.info("Booking refunded and dates released after refund",
            booking_id: booking.id,
            payment_id: payment_id
          )

          {:ok, :booking_refunded}

        {:error, reason} ->
          {:error, {:booking_refund_failed, reason}}
      end
    else
      # Try to find ticket order associated with this payment
      ticket_order =
        from(to in Ysc.Tickets.TicketOrder,
          where: to.payment_id == ^payment_id,
          where: to.status == :completed,
          limit: 1
        )
        |> Repo.one()

      if ticket_order do
        case Tickets.cancel_ticket_order(ticket_order, "Refund processed - tickets released") do
          {:ok, _canceled_order} ->
            require Logger

            Logger.info("Ticket order canceled and tickets released after refund",
              ticket_order_id: ticket_order.id,
              payment_id: payment_id
            )

            {:ok, :ticket_order_canceled}

          {:error, reason} ->
            {:error, {:ticket_order_cancel_failed, reason}}
        end
      else
        {:ok, :not_found}
      end
    end
  end
end
