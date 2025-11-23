defmodule Ysc.Quickbooks.Sync do
  @moduledoc """
  Handles syncing Payment, Refund, and Payout records to QuickBooks.

  This module provides functions to sync ledger records to QuickBooks Online,
  mapping entity types to the appropriate QuickBooks accounts and classes.
  """

  require Logger
  alias Ysc.Repo
  alias Ysc.Ledgers.{Payment, Refund, Payout, LedgerEntry}
  alias Ysc.Quickbooks
  alias Ysc.Accounts.User
  alias YscWeb.Workers.QuickbooksSyncPayoutWorker
  import Ecto.Query

  # QuickBooks Account and Class mappings
  @account_class_mapping %{
    # Event tickets
    event: %{account: "Events Inc", class: "Events"},
    # Donations
    donation: %{account: "Donations", class: "Administration"},
    # Clear Lake bookings
    clear_lake_booking: %{account: "Clear Lake Inc", class: "Clear Lake"},
    # Tahoe bookings
    tahoe_booking: %{account: "Tahoe Inc", class: "Tahoe"},
    # Stripe fees
    stripe_fee: %{account: "Stripe Fees", class: "Administration"}
  }

  @doc """
  Syncs a payment to QuickBooks as a SalesReceipt.

  Returns {:ok, sales_receipt} on success, {:error, reason} on failure.
  """
  @spec sync_payment(Payment.t()) :: {:ok, map()} | {:error, atom() | String.t()}
  def sync_payment(%Payment{} = payment) do
    # Check if already synced
    if payment.quickbooks_sync_status == "synced" && payment.quickbooks_sales_receipt_id do
      Logger.info("Payment already synced to QuickBooks",
        payment_id: payment.id,
        sales_receipt_id: payment.quickbooks_sales_receipt_id
      )

      # Even if already synced, check if any payouts are now ready to sync
      check_and_enqueue_payout_syncs_for_payment(payment)

      {:ok, %{"Id" => payment.quickbooks_sales_receipt_id}}
    else
      do_sync_payment(payment)
    end
  end

  @doc """
  Syncs a refund to QuickBooks as a SalesReceipt (negative amount).

  Returns {:ok, sales_receipt} on success, {:error, reason} on failure.
  """
  @spec sync_refund(Refund.t()) :: {:ok, map()} | {:error, atom() | String.t()}
  def sync_refund(%Refund{} = refund) do
    # Check if already synced
    if refund.quickbooks_sync_status == "synced" && refund.quickbooks_sales_receipt_id do
      Logger.info("Refund already synced to QuickBooks",
        refund_id: refund.id,
        sales_receipt_id: refund.quickbooks_sales_receipt_id
      )

      # Even if already synced, check if any payouts are now ready to sync
      check_and_enqueue_payout_syncs_for_refund(refund)

      {:ok, %{"Id" => refund.quickbooks_sales_receipt_id}}
    else
      do_sync_refund(refund)
    end
  end

  @doc """
  Syncs a payout to QuickBooks as a Deposit.

  Returns {:ok, deposit} on success, {:error, reason} on failure.
  """
  @spec sync_payout(Payout.t()) :: {:ok, map()} | {:error, atom() | String.t()}
  def sync_payout(%Payout{} = payout) do
    # Check if already synced
    if payout.quickbooks_sync_status == "synced" && payout.quickbooks_deposit_id do
      Logger.info("Payout already synced to QuickBooks",
        payout_id: payout.id,
        deposit_id: payout.quickbooks_deposit_id
      )

      {:ok, %{"Id" => payout.quickbooks_deposit_id}}
    else
      do_sync_payout(payout)
    end
  end

  # Private functions

  defp do_sync_payment(%Payment{} = payment) do
    # Reload payment to ensure we have the latest state
    payment = Repo.reload!(payment)

    # Mark as attempting sync
    update_sync_status(payment, "pending", nil, nil)

    # Reload again after status update to ensure we have the updated payment
    payment = Repo.reload!(payment)

    with {:ok, user} <- get_user(payment.user_id),
         {:ok, customer_id} <- get_or_create_customer(user),
         {:ok, entity_info} <- get_payment_entity_info(payment),
         {:ok, item_id} <- get_item_id_for_entity(entity_info),
         {:ok, sales_receipt} <-
           create_payment_sales_receipt(payment, customer_id, item_id, entity_info) do
      sales_receipt_id = Map.get(sales_receipt, "Id")

      # Update payment with sync success
      update_sync_success(payment, sales_receipt_id, sales_receipt)

      Logger.info("Successfully synced payment to QuickBooks",
        payment_id: payment.id,
        sales_receipt_id: sales_receipt_id
      )

      # Check if any payouts are now ready to sync
      check_and_enqueue_payout_syncs_for_payment(payment)

      {:ok, sales_receipt}
    else
      {:error, reason} = error ->
        # Update payment with sync failure
        update_sync_failure(payment, reason)
        error
    end
  end

  defp do_sync_refund(%Refund{} = refund) do
    # Mark as attempting sync
    update_sync_status_refund(refund, "pending", nil, nil)

    with {:ok, payment} <- get_payment(refund.payment_id),
         {:ok, user} <- get_user(payment.user_id),
         {:ok, customer_id} <- get_or_create_customer(user),
         {:ok, entity_info} <- get_payment_entity_info(payment),
         {:ok, item_id} <- get_quickbooks_item_id(entity_info),
         {:ok, sales_receipt} <-
           create_refund_sales_receipt(refund, customer_id, item_id, entity_info) do
      sales_receipt_id = Map.get(sales_receipt, "Id")

      # Update refund with sync success
      update_sync_success_refund(refund, sales_receipt_id, sales_receipt)

      Logger.info("Successfully synced refund to QuickBooks",
        refund_id: refund.id,
        sales_receipt_id: sales_receipt_id
      )

      # Check if any payouts are now ready to sync
      check_and_enqueue_payout_syncs_for_refund(refund)

      {:ok, sales_receipt}
    else
      {:error, reason} = error ->
        # Update refund with sync failure
        update_sync_failure_refund(refund, reason)
        error
    end
  end

  defp do_sync_payout(%Payout{} = payout) do
    # Mark as attempting sync
    update_sync_status_payout(payout, "pending", nil, nil)

    # Load payout with payments and refunds
    payout = Repo.preload(payout, [:payments, :refunds])

    # Verify all linked payments and refunds are synced before proceeding
    with :ok <- verify_all_transactions_synced(payout),
         {:ok, deposit} <- create_payout_deposit(payout) do
      deposit_id = Map.get(deposit, "Id")

      # Update payout with sync success
      update_sync_success_payout(payout, deposit_id, deposit)

      Logger.info("Successfully synced payout to QuickBooks",
        payout_id: payout.id,
        deposit_id: deposit_id,
        payments_count: length(payout.payments),
        refunds_count: length(payout.refunds)
      )

      {:ok, deposit}
    else
      {:error, reason} = error ->
        # Update payout with sync failure
        update_sync_failure_payout(payout, reason)
        error
    end
  end

  defp get_user(nil), do: {:error, :user_not_found}

  defp get_user(user_id) do
    case Repo.get(User, user_id) do
      nil -> {:error, :user_not_found}
      user -> {:ok, user}
    end
  end

  defp get_payment(payment_id) do
    case Repo.get(Payment, payment_id) do
      nil -> {:error, :payment_not_found}
      payment -> {:ok, payment}
    end
  end

  defp get_or_create_customer(user) do
    case Quickbooks.get_or_create_customer(user) do
      {:ok, customer_id} -> {:ok, customer_id}
      error -> error
    end
  end

  defp get_payment_entity_info(%Payment{} = payment) do
    # Get all revenue entries for this payment to detect mixed event/donation payments
    entries =
      from(e in LedgerEntry,
        join: a in assoc(e, :account),
        where: e.payment_id == ^payment.id,
        where: e.debit_credit == "credit",
        where: e.related_entity_type in ^["event", "booking", "donation", "membership"],
        where: a.account_type == "revenue",
        order_by: [desc: e.inserted_at],
        preload: [:account]
      )
      |> Repo.all()

    # Check if we have both event and donation entries (mixed payment)
    event_entry = Enum.find(entries, fn e -> e.related_entity_type in [:event, "event"] end)

    donation_entry =
      Enum.find(entries, fn e -> e.related_entity_type in [:donation, "donation"] end)

    cond do
      # Mixed event/donation payment
      event_entry && donation_entry ->
        {:ok,
         %{
           entity_type: :mixed_event_donation,
           property: nil,
           event_entry: event_entry,
           donation_entry: donation_entry,
           entries: entries
         }}

      # Single entity type payment
      event_entry ->
        entity_type =
          case event_entry.related_entity_type do
            atom when is_atom(atom) -> atom
            string when is_binary(string) -> String.to_existing_atom(string)
          end

        property =
          if entity_type == :booking do
            determine_booking_property(payment)
          else
            nil
          end

        {:ok, %{entity_type: entity_type, property: property, entry: event_entry}}

      donation_entry ->
        entity_type =
          case donation_entry.related_entity_type do
            atom when is_atom(atom) -> atom
            string when is_binary(string) -> String.to_existing_atom(string)
          end

        {:ok, %{entity_type: entity_type, property: nil, entry: donation_entry}}

      # Try to find any revenue entry
      entry = List.first(entries) ->
        entity_type =
          case entry.related_entity_type do
            atom when is_atom(atom) -> atom
            string when is_binary(string) -> String.to_existing_atom(string)
          end

        property =
          if entity_type == :booking do
            determine_booking_property(payment)
          else
            nil
          end

        {:ok, %{entity_type: entity_type, property: property, entry: entry}}

      # Default to membership if no entity type found
      true ->
        {:ok, %{entity_type: :membership, property: nil, entry: nil}}
    end
  end

  defp determine_booking_property(%Payment{} = payment) do
    # Check ledger entries for property indicators
    entries =
      from(e in LedgerEntry,
        where: e.payment_id == ^payment.id,
        where: ilike(e.description, "%tahoe%") or ilike(e.description, "%clear lake%")
      )
      |> Repo.all()

    case entries do
      [] ->
        # Check account name
        entries =
          from(e in LedgerEntry,
            join: a in assoc(e, :account),
            where: e.payment_id == ^payment.id,
            where: a.name in ["tahoe_booking_revenue", "clear_lake_booking_revenue"]
          )
          |> Repo.all()

        case entries do
          [%{account: %{name: "tahoe_booking_revenue"}} | _] -> :tahoe
          [%{account: %{name: "clear_lake_booking_revenue"}} | _] -> :clear_lake
          _ -> nil
        end

      [%{description: desc} | _] ->
        cond do
          String.contains?(String.downcase(desc), "tahoe") -> :tahoe
          String.contains?(String.downcase(desc), "clear lake") -> :clear_lake
          true -> nil
        end
    end
  end

  defp get_item_id_for_entity(%{entity_type: :mixed_event_donation}) do
    # For mixed payments, item_id is not needed (handled in create_payment_sales_receipt)
    {:ok, nil}
  end

  defp get_item_id_for_entity(entity_info) do
    get_quickbooks_item_id(entity_info)
  end

  defp get_quickbooks_item_id(%{entity_type: entity_type, property: property}) do
    # Map entity type to QuickBooks item ID
    # These should be configured in application config
    item_id =
      case {entity_type, property} do
        {:event, _} ->
          Application.get_env(:ysc, :quickbooks)[:event_item_id]

        {:donation, _} ->
          Application.get_env(:ysc, :quickbooks)[:donation_item_id]

        {:booking, :tahoe} ->
          Application.get_env(:ysc, :quickbooks)[:tahoe_booking_item_id]

        {:booking, :clear_lake} ->
          Application.get_env(:ysc, :quickbooks)[:clear_lake_booking_item_id]

        {:membership, _} ->
          Application.get_env(:ysc, :quickbooks)[:membership_item_id]

        _ ->
          Application.get_env(:ysc, :quickbooks)[:default_item_id]
      end

    if item_id do
      {:ok, item_id}
    else
      {:error, :quickbooks_item_id_not_configured}
    end
  end

  defp get_account_and_class(%{entity_type: entity_type, property: property}) do
    case {entity_type, property} do
      {:event, _} -> @account_class_mapping[:event]
      {:donation, _} -> @account_class_mapping[:donation]
      {:booking, :tahoe} -> @account_class_mapping[:tahoe_booking]
      {:booking, :clear_lake} -> @account_class_mapping[:clear_lake_booking]
      _ -> nil
    end
  end

  defp create_payment_sales_receipt(payment, customer_id, item_id, entity_info) do
    # Handle mixed event/donation payments with separate line items
    if entity_info.entity_type == :mixed_event_donation do
      create_mixed_payment_sales_receipt(payment, customer_id, entity_info)
    else
      # Single entity type payment - use existing logic
      # Convert from cents to dollars for QuickBooks
      amount =
        Money.to_decimal(payment.amount)
        |> Decimal.div(Decimal.new(100))
        |> Decimal.round(2)

      account_class = get_account_and_class(entity_info)

      params = %{
        customer_id: customer_id,
        item_id: item_id,
        quantity: 1,
        unit_price: amount,
        txn_date: payment.payment_date || payment.inserted_at,
        description: "Payment #{payment.reference_id}",
        memo: "Payment: #{payment.reference_id}",
        private_note: "External Payment ID: #{payment.external_payment_id}"
      }

      params =
        if account_class do
          params
          |> Map.put(:class_ref, account_class.class)
        else
          params
        end

      Quickbooks.create_purchase_sales_receipt(params)
    end
  end

  defp create_mixed_payment_sales_receipt(payment, customer_id, entity_info) do
    # Get item IDs for event and donation
    event_item_id = Application.get_env(:ysc, :quickbooks)[:event_item_id]
    donation_item_id = Application.get_env(:ysc, :quickbooks)[:donation_item_id]

    if is_nil(event_item_id) or is_nil(donation_item_id) do
      {:error, :quickbooks_item_ids_not_configured}
    else
      # Build line items - only include non-zero amounts
      line_items = []

      # Add event line item if event entry exists and has positive amount
      line_items =
        if entity_info.event_entry && Money.positive?(entity_info.event_entry.amount) do
          event_amount =
            Money.to_decimal(entity_info.event_entry.amount)
            |> Decimal.div(Decimal.new(100))
            |> Decimal.round(2)

          event_line_item =
            build_sales_line_item(
              event_item_id,
              event_amount,
              "Event tickets - Order #{payment.reference_id}",
              @account_class_mapping[:event].class
            )

          [event_line_item | line_items]
        else
          line_items
        end

      # Add donation line item if donation entry exists and has positive amount
      line_items =
        if entity_info.donation_entry && Money.positive?(entity_info.donation_entry.amount) do
          donation_amount =
            Money.to_decimal(entity_info.donation_entry.amount)
            |> Decimal.div(Decimal.new(100))
            |> Decimal.round(2)

          donation_line_item =
            build_sales_line_item(
              donation_item_id,
              donation_amount,
              "Donation - Order #{payment.reference_id}",
              @account_class_mapping[:donation].class
            )

          [donation_line_item | line_items]
        else
          line_items
        end

      # Calculate total from line items
      total_amount =
        Enum.reduce(line_items, Decimal.new(0), fn item, acc ->
          Decimal.add(acc, item.amount)
        end)

      # Build sales receipt params
      sales_receipt_params = %{
        customer_ref: %{value: customer_id},
        line: Enum.reverse(line_items),
        total_amt: total_amount,
        txn_date: format_payment_date(payment.payment_date || payment.inserted_at),
        memo: "Payment: #{payment.reference_id}",
        private_note: "External Payment ID: #{payment.external_payment_id}"
      }

      # Use client directly to create sales receipt with multiple line items
      client_module = Application.get_env(:ysc, :quickbooks_client, Ysc.Quickbooks.Client)
      client_module.create_sales_receipt(sales_receipt_params)
    end
  end

  defp build_sales_line_item(item_id, amount, description, class_ref) do
    sales_item_detail = %{
      item_ref: %{value: item_id},
      quantity: Decimal.new(1),
      unit_price: amount
    }

    sales_item_detail =
      if class_ref do
        Map.put(sales_item_detail, :class_ref, %{value: class_ref})
      else
        sales_item_detail
      end

    %{
      amount: amount,
      detail_type: "SalesItemLineDetail",
      sales_item_line_detail: sales_item_detail,
      description: description
    }
  end

  defp format_payment_date(%DateTime{} = datetime) do
    datetime
    |> DateTime.to_date()
    |> Date.to_iso8601()
  end

  defp format_payment_date(nil), do: nil

  defp create_refund_sales_receipt(refund, customer_id, item_id, entity_info) do
    # Convert from cents to dollars for QuickBooks (will be negated later)
    amount =
      Money.to_decimal(refund.amount)
      |> Decimal.div(Decimal.new(100))
      |> Decimal.round(2)

    account_class = get_account_and_class(entity_info)

    # Get the original payment's QuickBooks SalesReceipt ID if available
    original_payment = get_payment(refund.payment_id)

    private_note =
      case original_payment do
        {:ok, payment}
        when not is_nil(payment.quickbooks_sales_receipt_id) and
               payment.quickbooks_sales_receipt_id != "" and
               payment.quickbooks_sales_receipt_id != "qb_sr_default" and
               payment.quickbooks_sync_status == "synced" ->
          "External Refund ID: #{refund.external_refund_id}\nOriginal Payment SalesReceipt: #{payment.quickbooks_sales_receipt_id}"

        _ ->
          "External Refund ID: #{refund.external_refund_id}"
      end

    params = %{
      customer_id: customer_id,
      item_id: item_id,
      quantity: 1,
      unit_price: amount,
      txn_date: refund.inserted_at,
      description: "Refund #{refund.reference_id}",
      memo: "Refund: #{refund.reference_id}",
      private_note: private_note
    }

    params =
      if account_class do
        params
        |> Map.put(:class_ref, account_class.class)
      else
        params
      end

    Quickbooks.create_refund_sales_receipt(params)
  end

  defp create_payout_deposit(%Payout{} = payout) do
    bank_account_id = Application.get_env(:ysc, :quickbooks)[:bank_account_id]
    stripe_account_id = Application.get_env(:ysc, :quickbooks)[:stripe_account_id]

    if bank_account_id && stripe_account_id do
      # Build line items for each payment and refund
      line_items = build_payout_line_items(payout)

      if Enum.empty?(line_items) do
        Logger.warning(
          "No synced payments or refunds found for payout, creating single line item",
          payout_id: payout.id
        )

        # Fallback: create single line item with total amount
        # Convert from cents to dollars for QuickBooks
        amount =
          Money.to_decimal(payout.amount)
          |> Decimal.div(Decimal.new(100))
          |> Decimal.round(2)

        params = %{
          bank_account_id: bank_account_id,
          stripe_account_id: stripe_account_id,
          amount: amount,
          txn_date: payout.arrival_date || payout.inserted_at,
          memo: "Stripe Payout: #{payout.stripe_payout_id}",
          description: payout.description || "Stripe payout",
          class_ref: "Administration"
        }

        Quickbooks.create_stripe_payout_deposit(params)
      else
        # Calculate total from line items
        total_amount =
          Enum.reduce(line_items, Decimal.new(0), fn item, acc ->
            Decimal.add(acc, item.amount)
          end)

        # Create deposit with multiple line items
        create_payout_deposit_with_lines(payout, bank_account_id, line_items, total_amount)
      end
    else
      {:error, :quickbooks_accounts_not_configured}
    end
  end

  defp build_payout_line_items(%Payout{payments: payments, refunds: refunds}) do
    # Build line items for payments (positive amounts)
    payment_lines =
      Enum.map(payments, fn payment ->
        # Only include payments that have been synced to QuickBooks
        if payment.quickbooks_sync_status == "synced" && payment.quickbooks_sales_receipt_id do
          # Convert from cents to dollars for QuickBooks
          amount =
            Money.to_decimal(payment.amount)
            |> Decimal.div(Decimal.new(100))
            |> Decimal.round(2)

          %{
            amount: amount,
            detail_type: "DepositLineDetail",
            deposit_line_detail: %{
              entity_ref: %{
                value: payment.quickbooks_sales_receipt_id,
                type: "SalesReceipt"
              }
            },
            description: "Payment #{payment.reference_id}"
          }
        else
          nil
        end
      end)
      |> Enum.filter(&(&1 != nil))

    # Build line items for refunds (negative amounts)
    refund_lines =
      Enum.map(refunds, fn refund ->
        # Only include refunds that have been synced to QuickBooks
        if refund.quickbooks_sync_status == "synced" && refund.quickbooks_sales_receipt_id do
          # Convert from cents to dollars for QuickBooks, then negate (refunds are negative)
          amount =
            Money.to_decimal(refund.amount)
            |> Decimal.div(Decimal.new(100))
            |> Decimal.round(2)
            |> Decimal.negate()

          %{
            amount: amount,
            detail_type: "DepositLineDetail",
            deposit_line_detail: %{
              entity_ref: %{
                value: refund.quickbooks_sales_receipt_id,
                type: "SalesReceipt"
              }
            },
            description: "Refund #{refund.reference_id}"
          }
        else
          nil
        end
      end)
      |> Enum.filter(&(&1 != nil))

    payment_lines ++ refund_lines
  end

  defp create_payout_deposit_with_lines(payout, bank_account_id, line_items, total_amount) do
    # Build deposit params with line items in the format expected by Client.create_deposit
    deposit_params = %{
      deposit_to_account_ref: %{value: bank_account_id},
      line: line_items,
      total_amt: total_amount,
      txn_date: format_payout_date(payout.arrival_date || payout.inserted_at),
      memo: "Stripe Payout: #{payout.stripe_payout_id}",
      private_note:
        "Payout includes #{length(payout.payments)} payments and #{length(payout.refunds)} refunds"
    }

    # Use the client directly to create deposit with custom line items
    client_module = Application.get_env(:ysc, :quickbooks_client, Ysc.Quickbooks.Client)
    client_module.create_deposit(deposit_params)
  end

  defp format_payout_date(%DateTime{} = datetime) do
    datetime
    |> DateTime.to_date()
    |> Date.to_iso8601()
  end

  defp format_payout_date(nil), do: nil

  defp check_and_enqueue_payout_syncs_for_payment(%Payment{} = payment) do
    # Find all payouts that contain this payment
    # Convert ULID to binary for comparison with join table's binary_id column
    payment_id_binary =
      case Ecto.ULID.dump(payment.id) do
        {:ok, binary} -> binary
        _ -> payment.id
      end

    payouts =
      from(p in Payout,
        join: pp in "payout_payments",
        on: pp.payout_id == p.id,
        where: pp.payment_id == ^payment_id_binary,
        where: p.quickbooks_sync_status != "synced"
      )
      |> Repo.all()

    Enum.each(payouts, fn payout ->
      check_and_enqueue_payout_sync(payout)
    end)
  end

  defp check_and_enqueue_payout_syncs_for_refund(%Refund{} = refund) do
    # Find all payouts that contain this refund
    # Convert ULID to binary for comparison with join table's binary_id column
    refund_id_binary =
      case Ecto.ULID.dump(refund.id) do
        {:ok, binary} -> binary
        _ -> refund.id
      end

    payouts =
      from(p in Payout,
        join: pr in "payout_refunds",
        on: pr.payout_id == p.id,
        where: pr.refund_id == ^refund_id_binary,
        where: p.quickbooks_sync_status != "synced"
      )
      |> Repo.all()

    Enum.each(payouts, fn payout ->
      check_and_enqueue_payout_sync(payout)
    end)
  end

  defp check_and_enqueue_payout_sync(%Payout{} = payout) do
    # Reload payout with payments and refunds
    payout = Repo.preload(payout, [:payments, :refunds])

    # Check if all linked payments are synced
    all_payments_synced =
      Enum.all?(payout.payments, fn payment ->
        payment.quickbooks_sync_status == "synced" && payment.quickbooks_sales_receipt_id != nil
      end)

    # Check if all linked refunds are synced
    all_refunds_synced =
      Enum.all?(payout.refunds, fn refund ->
        refund.quickbooks_sync_status == "synced" && refund.quickbooks_sales_receipt_id != nil
      end)

    # Only enqueue if we have transactions and they're all synced
    if all_payments_synced && all_refunds_synced &&
         (length(payout.payments) > 0 || length(payout.refunds) > 0) do
      Logger.info("All payments and refunds synced, enqueueing QuickBooks sync for payout",
        payout_id: payout.id,
        payments_count: length(payout.payments),
        refunds_count: length(payout.refunds)
      )

      # Mark payout as pending sync
      payout
      |> Payout.changeset(%{quickbooks_sync_status: "pending"})
      |> Repo.update()

      # Enqueue sync job
      %{payout_id: to_string(payout.id)}
      |> QuickbooksSyncPayoutWorker.new()
      |> Oban.insert()
    end
  end

  defp verify_all_transactions_synced(%Payout{payments: payments, refunds: refunds}) do
    # Check all payments are synced
    unsynced_payments =
      Enum.filter(payments, fn payment ->
        payment.quickbooks_sync_status != "synced" || payment.quickbooks_sales_receipt_id == nil
      end)

    # Check all refunds are synced
    unsynced_refunds =
      Enum.filter(refunds, fn refund ->
        refund.quickbooks_sync_status != "synced" || refund.quickbooks_sales_receipt_id == nil
      end)

    if Enum.empty?(unsynced_payments) && Enum.empty?(unsynced_refunds) do
      :ok
    else
      Logger.warning("Cannot sync payout - some payments or refunds are not synced yet",
        unsynced_payments_count: length(unsynced_payments),
        unsynced_refunds_count: length(unsynced_refunds),
        total_payments: length(payments),
        total_refunds: length(refunds)
      )

      {:error, :transactions_not_fully_synced}
    end
  end

  # Update functions for Payment
  defp update_sync_status(%Payment{} = payment, status, error, response) do
    payment
    |> Payment.changeset(%{
      quickbooks_sync_status: status,
      quickbooks_sync_error: error,
      quickbooks_response: response,
      quickbooks_last_sync_attempt_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  defp update_sync_success(%Payment{} = payment, sales_receipt_id, response) do
    payment
    |> Payment.changeset(%{
      quickbooks_sales_receipt_id: sales_receipt_id,
      quickbooks_sync_status: "synced",
      quickbooks_synced_at: DateTime.utc_now(),
      quickbooks_response: response,
      quickbooks_last_sync_attempt_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  defp update_sync_failure(%Payment{} = payment, reason) do
    error_map = %{
      error: inspect(reason),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    # Reload payment to ensure we have the latest state
    payment = Repo.reload!(payment)

    case payment
         |> Payment.changeset(%{
           quickbooks_sync_status: "failed",
           quickbooks_sync_error: error_map,
           quickbooks_last_sync_attempt_at: DateTime.utc_now()
         })
         |> Repo.update() do
      {:ok, _updated_payment} ->
        :ok

      {:error, changeset} ->
        Logger.error("Failed to update payment sync failure",
          payment_id: payment.id,
          error: inspect(changeset.errors)
        )
    end
  end

  # Update functions for Refund
  defp update_sync_status_refund(%Refund{} = refund, status, error, response) do
    refund
    |> Refund.changeset(%{
      quickbooks_sync_status: status,
      quickbooks_sync_error: error,
      quickbooks_response: response,
      quickbooks_last_sync_attempt_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  defp update_sync_success_refund(%Refund{} = refund, sales_receipt_id, response) do
    refund
    |> Refund.changeset(%{
      quickbooks_sales_receipt_id: sales_receipt_id,
      quickbooks_sync_status: "synced",
      quickbooks_synced_at: DateTime.utc_now(),
      quickbooks_response: response,
      quickbooks_last_sync_attempt_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  defp update_sync_failure_refund(%Refund{} = refund, reason) do
    error_map = %{
      error: inspect(reason),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    refund
    |> Refund.changeset(%{
      quickbooks_sync_status: "failed",
      quickbooks_sync_error: error_map,
      quickbooks_last_sync_attempt_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  # Update functions for Payout
  defp update_sync_status_payout(%Payout{} = payout, status, error, response) do
    payout
    |> Payout.changeset(%{
      quickbooks_sync_status: status,
      quickbooks_sync_error: error,
      quickbooks_response: response,
      quickbooks_last_sync_attempt_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  defp update_sync_success_payout(%Payout{} = payout, deposit_id, response) do
    payout
    |> Payout.changeset(%{
      quickbooks_deposit_id: deposit_id,
      quickbooks_sync_status: "synced",
      quickbooks_synced_at: DateTime.utc_now(),
      quickbooks_response: response,
      quickbooks_last_sync_attempt_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  defp update_sync_failure_payout(%Payout{} = payout, reason) do
    error_map = %{
      error: inspect(reason),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    payout
    |> Payout.changeset(%{
      quickbooks_sync_status: "failed",
      quickbooks_sync_error: error_map,
      quickbooks_last_sync_attempt_at: DateTime.utc_now()
    })
    |> Repo.update()
  end
end
