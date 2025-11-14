defmodule Ysc.Stripe.WebhookHandler do
  @moduledoc """
  Handles incoming webhook events from Stripe.

  Processes various Stripe webhook event types including subscriptions,
  payments, invoices, and customer updates.
  """
  import Ecto.Query, warn: false
  alias Ysc.Customers
  alias Ysc.Subscriptions
  alias Ysc.Ledgers
  alias Ysc.MoneyHelper

  def handle_event(event) do
    require Logger
    Logger.info("Processing Stripe webhook event", event_id: event.id, event_type: event.type)

    # Write the webhook event to the database first
    # IF already exists, try to lock and process it
    try do
      Ysc.Webhooks.create_webhook_event!(%{
        provider: "stripe",
        event_id: event.id,
        event_type: event.type,
        payload: stripe_event_to_map(event)
      })

      # Lock and process the newly created event
      case Ysc.Webhooks.lock_webhook_event_by_provider_and_event_id("stripe", event.id) do
        {:ok, webhook_event} ->
          Logger.info("Locked newly created webhook event for processing",
            event_id: event.id,
            event_type: event.type
          )

          process_webhook_event(webhook_event, event)

        {:error, :already_processing} ->
          Logger.info("Newly created webhook event already being processed, skipping",
            event_id: event.id,
            event_type: event.type
          )

          :ok

        {:error, :not_found} ->
          Logger.error("Newly created webhook event not found after creation",
            event_id: event.id,
            event_type: event.type
          )

          :ok
      end
    rescue
      Ysc.Webhooks.DuplicateWebhookEventError ->
        # Event already exists, try to lock and process it
        case Ysc.Webhooks.lock_webhook_event_by_provider_and_event_id("stripe", event.id) do
          {:ok, webhook_event} ->
            Logger.info("Locked existing webhook event for processing",
              event_id: event.id,
              event_type: event.type
            )

            process_webhook_event(webhook_event, event)

          {:error, :already_processing} ->
            Logger.info("Webhook event already being processed, skipping",
              event_id: event.id,
              event_type: event.type
            )

            :ok

          {:error, :not_found} ->
            Logger.error("Webhook event not found after duplicate error",
              event_id: event.id,
              event_type: event.type
            )

            :ok
        end
    end
  end

  defp process_webhook_event(webhook_event, event) do
    require Logger

    try do
      # Process the webhook event
      result = handle(event.type, event.data.object)

      # Mark as processed
      Ysc.Webhooks.update_webhook_state(webhook_event, :processed)

      Logger.info("Webhook event processed successfully",
        event_id: event.id,
        event_type: event.type
      )

      result
    rescue
      error ->
        # Mark as failed
        Ysc.Webhooks.update_webhook_state(webhook_event, :failed)

        Logger.error("Webhook event processing failed",
          event_id: event.id,
          event_type: event.type,
          error: Exception.message(error)
        )

        :ok
    end
  end

  defp handle("customer.deleted", %Stripe.Customer{} = event) do
    user = Ysc.Accounts.get_user_from_stripe_id(event.id)

    if user do
      user
      |> Customers.subscriptions()
      |> Enum.each(&Subscriptions.mark_as_cancelled/1)
    end

    :ok
  end

  defp handle("customer.updated", %Stripe.Customer{} = event) do
    user = Ysc.Accounts.get_user_from_stripe_id(event.id)

    if user do
      # Temporarily disable automatic syncing to prevent race conditions
      # The user-initiated payment method selection should handle this
      require Logger

      Logger.info(
        "Customer updated webhook received, skipping automatic sync to prevent race conditions",
        user_id: user.id,
        customer_id: event.id
      )
    end

    :ok
  end

  defp handle("customer.subscription.created", %Stripe.Subscription{} = event) do
    customer = Ysc.Accounts.get_user_from_stripe_id(event.customer)
    Subscriptions.create_subscription_from_stripe(customer, event)

    :ok
  end

  defp handle("customer.subscription.deleted", %Stripe.Subscription{} = event) do
    subscription = Subscriptions.get_subscription_by_stripe_id(event.id)

    if subscription do
      Subscriptions.mark_as_cancelled(subscription)
    end

    :ok
  end

  defp handle("customer.subscription.updated", %Stripe.Subscription{} = event) do
    subscription = Subscriptions.get_subscription_by_stripe_id(event.id)

    if subscription do
      status = event.status

      if status == "incomplete_expired" do
        Subscriptions.delete_subscription(subscription)
      else
        # Update subscription
        user = Ysc.Accounts.get_user_from_stripe_id(event.customer)

        subscription_changeset =
          Subscriptions.subscription_struct_from_stripe_subscription(user, event)
          |> maybe_put_cancellation_end(event)

        case Ysc.Repo.update(subscription_changeset) do
          {:ok, updated_subscription} ->
            # Update subscription items
            update_subscription_items(updated_subscription, event.items.data)

          {:error, _changeset} ->
            :ok
        end
      end
    end

    :ok
  end

  # Grouped subscription_schedule handlers
  defp handle("subscription_schedule.created", %Stripe.SubscriptionSchedule{} = _schedule),
    do: :ok

  defp handle("subscription_schedule.updated", %Stripe.SubscriptionSchedule{} = _schedule),
    do: :ok

  defp handle("subscription_schedule.released", %Stripe.SubscriptionSchedule{} = _schedule),
    do: :ok

  defp handle("subscription_schedule.canceled", %Stripe.SubscriptionSchedule{} = _schedule),
    do: :ok

  defp handle("payment_method.attached", %Stripe.PaymentMethod{} = payment_method) do
    user = Ysc.Accounts.get_user_from_stripe_id(payment_method.customer)

    if user do
      # Just sync the payment method data without changing default status
      case Ysc.Payments.sync_payment_method_from_stripe(user, payment_method) do
        {:ok, _payment_method_record} ->
          # Payment method created/updated successfully
          :ok

        {:error, _} ->
          # Still log the error but don't fail the webhook
          require Logger

          Logger.warning("Failed to upsert payment method from Stripe webhook",
            user_id: user.id,
            payment_method_id: payment_method.id
          )
      end
    end

    :ok
  end

  defp handle("payment_method.detached", %Stripe.PaymentMethod{} = payment_method) do
    case Ysc.Payments.get_payment_method_by_provider(:stripe, payment_method.id) do
      nil -> :ok
      existing_payment_method -> Ysc.Payments.delete_payment_method(existing_payment_method)
    end

    :ok
  end

  defp handle("payment_method.updated", %Stripe.PaymentMethod{} = payment_method) do
    user = Ysc.Accounts.get_user_from_stripe_id(payment_method.customer)

    if user do
      # Just sync the payment method data without changing default status
      Ysc.Payments.sync_payment_method_from_stripe(user, payment_method)
    end

    :ok
  end

  defp handle("setup_intent.created", %Stripe.SetupIntent{} = setup_intent) do
    require Logger

    Logger.info("Setup intent created",
      setup_intent_id: setup_intent.id,
      user_id: setup_intent.customer
    )

    :ok
  end

  defp handle("setup_intent.succeeded", %Stripe.SetupIntent{} = setup_intent) do
    user = Ysc.Accounts.get_user_from_stripe_id(setup_intent.customer)

    if user && setup_intent.payment_method do
      # When setup intent succeeds, the payment method should already be handled by payment_method.attached
      # If it's not found, it will be handled when payment_method.attached is received
      case Ysc.Payments.get_payment_method_by_provider(:stripe, setup_intent.payment_method) do
        nil ->
          # Payment method not found in our system yet, it will be handled by payment_method.attached
          :ok

        _payment_method_record ->
          # Payment method exists, default setting is already handled by upsert_payment_method_from_stripe
          :ok
      end
    end

    :ok
  end

  defp handle("invoice.payment_action_required", %Stripe.Invoice{} = _invoice) do
    :ok
  end

  defp handle("invoice.payment.failed", %Stripe.Invoice{} = _invoice) do
    :ok
  end

  defp handle("invoice.payment_succeeded", %Stripe.Invoice{} = invoice) do
    # Convert Stripe struct to map and call the map handler
    invoice_map = %{
      id: invoice.id,
      customer: invoice.customer,
      subscription: invoice.subscription,
      amount_paid: invoice.amount_paid,
      description: invoice.description,
      number: invoice.number,
      charge: invoice.charge,
      metadata: invoice.metadata
    }

    handle("invoice.payment_succeeded", invoice_map)
  end

  defp handle("invoice.payment_succeeded", invoice) when is_map(invoice) do
    require Logger

    # This webhook is specifically for subscription payments
    # It's more reliable than payment_intent.succeeded for subscription billing
    # Handle both atom and string keys for compatibility
    subscription_id = invoice[:subscription] || invoice["subscription"]

    case subscription_id do
      nil ->
        # Not a subscription invoice, skip
        :ok

      subscription_id ->
        # Get the user from the customer ID
        customer_id = invoice[:customer] || invoice["customer"]
        invoice_id = invoice[:id] || invoice["id"]
        user = Ysc.Accounts.get_user_from_stripe_id(customer_id)

        if user do
          # Check if we already have a payment record for this invoice
          existing_payment = Ledgers.get_payment_by_external_id(invoice_id)

          if existing_payment do
            Logger.info("Payment already exists for invoice",
              invoice_id: invoice_id,
              payment_id: existing_payment.id
            )

            :ok
          else
            # Process the subscription payment with ledger entries
            amount_paid = invoice[:amount_paid] || invoice["amount_paid"]
            description = invoice[:description] || invoice["description"]
            number = invoice[:number] || invoice["number"]

            payment_attrs = %{
              user_id: user.id,
              amount: Money.new(:USD, MoneyHelper.cents_to_dollars(amount_paid)),
              entity_type: :membership,
              entity_id: find_subscription_id_from_stripe_id(subscription_id, user),
              external_payment_id: invoice_id,
              stripe_fee: extract_stripe_fee_from_invoice(invoice),
              description: "Membership payment - #{description || "Invoice #{number}"}",
              property: nil,
              payment_method_id: extract_payment_method_from_invoice(invoice)
            }

            case Ledgers.process_payment(payment_attrs) do
              {:ok, {_payment, _transaction, _entries}} ->
                Logger.info("Subscription payment processed successfully in ledger",
                  invoice_id: invoice_id,
                  user_id: user.id,
                  subscription_id: subscription_id
                )

                :ok

              {:error, reason} ->
                Logger.error("Failed to process subscription payment in ledger",
                  invoice_id: invoice_id,
                  user_id: user.id,
                  error: reason
                )

                :ok
            end
          end
        else
          Logger.warning("No user found for invoice payment",
            invoice_id: invoice_id,
            customer_id: customer_id
          )

          :ok
        end
    end
  end

  defp handle("payment_intent.succeeded", %Stripe.PaymentIntent{} = payment_intent) do
    # Convert Stripe struct to map and call the map handler
    payment_intent_map = %{
      id: payment_intent.id,
      status: payment_intent.status,
      customer: payment_intent.customer,
      amount: payment_intent.amount,
      description: payment_intent.description,
      metadata: payment_intent.metadata,
      # latest_charge might not exist on all PaymentIntent structs
      latest_charge: Map.get(payment_intent, :latest_charge)
    }

    handle("payment_intent.succeeded", payment_intent_map)
  end

  defp handle("payment_intent.succeeded", payment_intent) when is_map(payment_intent) do
    require Logger

    Logger.info("Payment intent succeeded",
      payment_intent_id: payment_intent.id,
      payment_intent_status: payment_intent.status,
      customer_id: payment_intent.customer
    )

    :ok
  end

  defp handle("payout.paid", %Stripe.Payout{} = payout) do
    # Convert Stripe struct to map and call the map handler
    payout_map = %{
      id: payout.id,
      amount: payout.amount,
      currency: payout.currency,
      status: payout.status,
      arrival_date: payout.arrival_date,
      description: payout.description,
      metadata: payout.metadata
    }

    handle("payout.paid", payout_map)
  end

  defp handle("payout.paid", payout) when is_map(payout) do
    require Logger

    payout_id = payout[:id] || payout["id"]

    Logger.info("Processing Stripe payout",
      payout_id: payout_id,
      amount: payout[:amount] || payout["amount"],
      currency: payout[:currency] || payout["currency"],
      status: payout[:status] || payout["status"]
    )

    # Check if payout already exists (idempotency)
    case Ledgers.get_payout_by_stripe_id(payout_id) do
      nil ->
        # Payout doesn't exist, process it
        process_new_payout(payout)

      existing_payout ->
        # Payout already exists, skip processing
        Logger.info("Payout already processed, skipping (idempotency)",
          payout_id: payout_id,
          existing_payout_id: existing_payout.id
        )

        :ok
    end
  end

  # Helper function to process a new payout
  defp process_new_payout(payout) do
    require Logger

    payout_id = payout[:id] || payout["id"]
    amount_cents = payout[:amount] || payout["amount"]
    currency_str = payout[:currency] || payout["currency"]
    currency = currency_str |> String.downcase() |> String.to_atom()
    description = payout[:description] || payout["description"] || "Stripe payout"
    status = payout[:status] || payout["status"]
    metadata = payout[:metadata] || payout["metadata"] || %{}

    # Parse arrival_date if present
    arrival_date =
      case payout[:arrival_date] || payout["arrival_date"] do
        nil ->
          nil

        unix_timestamp when is_integer(unix_timestamp) ->
          DateTime.from_unix!(unix_timestamp) |> DateTime.truncate(:second)

        _ ->
          nil
      end

    # Convert amount from cents to Money struct
    payout_amount = Money.new(currency, MoneyHelper.cents_to_dollars(amount_cents))

    # Process the payout in the ledger
    case Ledgers.process_stripe_payout(%{
           payout_amount: payout_amount,
           stripe_payout_id: payout_id,
           description: description,
           currency: currency_str,
           status: status,
           arrival_date: arrival_date,
           metadata: metadata
         }) do
      {:ok, {_payout_payment, _transaction, _entries, payout}} ->
        Logger.info("Stripe payout processed successfully in ledger",
          payout_id: payout_id,
          amount: Money.to_string!(payout_amount)
        )

        # Fetch and link payments/refunds from Stripe
        link_payout_transactions(payout, payout_id)

        :ok

      {:error, reason} ->
        Logger.error("Failed to process Stripe payout in ledger",
          payout_id: payout_id,
          amount: Money.to_string!(payout_amount),
          error: reason
        )

        :ok
    end
  end

  defp handle("charge.dispute.created", %Stripe.Dispute{} = dispute) do
    require Logger

    # Handle chargeback/dispute - you may want to create a liability entry
    Logger.info("Chargeback/dispute created",
      dispute_id: dispute.id,
      charge_id: dispute.charge
    )

    # You could add logic here to create ledger entries for disputes
    :ok
  end

  defp handle("charge.refunded", %Stripe.Charge{} = charge) do
    require Logger

    Logger.info("Charge refunded",
      charge_id: charge.id,
      payment_intent_id: charge.payment_intent
    )

    # Process refund in ledger
    process_refund_from_charge(charge)

    :ok
  end

  defp handle("refund.created", %Stripe.Refund{} = refund) do
    require Logger

    Logger.info("Refund created",
      refund_id: refund.id,
      charge_id: refund.charge,
      amount: refund.amount
    )

    # Process refund in ledger
    process_refund_from_refund_object(refund)

    :ok
  end

  defp handle("refund.created", refund) when is_map(refund) do
    require Logger

    refund_id = Map.get(refund, :id) || Map.get(refund, "id")
    charge_id = Map.get(refund, :charge) || Map.get(refund, "charge")
    amount = Map.get(refund, :amount) || Map.get(refund, "amount")

    Logger.info("Refund created",
      refund_id: refund_id,
      charge_id: charge_id,
      amount: amount
    )

    # Process refund in ledger
    process_refund_from_refund_object(refund)

    :ok
  end

  defp handle("refund.updated", %Stripe.Refund{} = refund) do
    require Logger

    Logger.info("Refund updated",
      refund_id: refund.id,
      charge_id: refund.charge,
      status: refund.status
    )

    # Only process if refund is now succeeded
    if refund.status == "succeeded" do
      process_refund_from_refund_object(refund)
    end

    :ok
  end

  defp handle("refund.updated", refund) when is_map(refund) do
    require Logger

    refund_id = Map.get(refund, :id) || Map.get(refund, "id")
    charge_id = Map.get(refund, :charge) || Map.get(refund, "charge")
    status = Map.get(refund, :status) || Map.get(refund, "status")

    Logger.info("Refund updated",
      refund_id: refund_id,
      charge_id: charge_id,
      status: status
    )

    # Only process if refund is now succeeded
    if status == "succeeded" do
      process_refund_from_refund_object(refund)
    end

    :ok
  end

  defp handle(_event_name, _event_object), do: :ok

  defp maybe_put_cancellation_end(changeset, %Stripe.Subscription{} = event) do
    ends_at =
      case Map.get(event, :cancel_at_period_end) do
        true ->
          event.current_period_end
          |> DateTime.from_unix!()
          |> DateTime.truncate(:second)

        _ ->
          nil
      end

    Ecto.Changeset.change(changeset, %{ends_at: ends_at})
  end

  @doc """
  Public function to handle webhook events by type and data object.
  This is used by the webhook reprocessor to re-process failed webhooks.
  """
  def handle_webhook_event(event_type, event_object) do
    handle(event_type, event_object)
  end

  # Convert Stripe.Event struct to a plain map for JSON storage
  defp stripe_event_to_map(%Stripe.Event{} = event) do
    %{
      id: event.id,
      object: event.object,
      api_version: event.api_version,
      created: event.created,
      data: convert_to_map(event.data),
      livemode: event.livemode,
      pending_webhooks: event.pending_webhooks,
      request: convert_to_map(event.request),
      type: event.type,
      account: event.account
    }
  end

  # Recursively convert any Stripe structs to maps
  defp convert_to_map(%{__struct__: _module} = struct) do
    # Convert any struct to a map
    Map.from_struct(struct)
    |> Enum.map(fn {key, value} -> {key, convert_to_map(value)} end)
    |> Enum.into(%{})
  end

  defp convert_to_map(%{} = map) do
    # Convert nested maps
    Enum.map(map, fn {key, value} -> {key, convert_to_map(value)} end)
    |> Enum.into(%{})
  end

  defp convert_to_map(list) when is_list(list) do
    Enum.map(list, &convert_to_map/1)
  end

  defp convert_to_map(value), do: value

  # Helper functions for extracting data from payment intents

  # Helper function to fetch actual Stripe fee from charge
  defp fetch_actual_stripe_fee_from_charge(charge_id) when is_binary(charge_id) do
    require Logger

    try do
      # Fetch the charge with expanded balance transaction to get actual fees
      case Stripe.Charge.retrieve(charge_id, expand: ["balance_transaction"]) do
        {:ok, %Stripe.Charge{balance_transaction: %Stripe.BalanceTransaction{fee: fee}}} ->
          # fee is already in cents
          Money.new(:USD, MoneyHelper.cents_to_dollars(fee))

        {:ok, %Stripe.Charge{}} ->
          Logger.warning("Charge retrieved but no balance transaction fee found",
            charge_id: charge_id
          )

          # Fallback to estimated fee
          calculate_estimated_fee_from_charge_amount(charge_id)

        {:error, reason} ->
          Logger.error("Failed to fetch charge for fee calculation",
            charge_id: charge_id,
            error: reason
          )

          # Fallback to estimated fee
          calculate_estimated_fee_from_charge_amount(charge_id)
      end
    rescue
      error ->
        Logger.error("Exception while fetching charge for fee calculation",
          charge_id: charge_id,
          error: Exception.message(error)
        )

        # Fallback to estimated fee
        calculate_estimated_fee_from_charge_amount(charge_id)
    end
  end

  defp fetch_actual_stripe_fee_from_charge(nil) do
    require Logger
    Logger.warning("No charge ID provided for fee calculation")
    # Return zero fee if no charge ID
    Money.new(0, :USD)
  end

  # Helper function to calculate estimated fee when we can't fetch actual fee
  defp calculate_estimated_fee_from_charge_amount(charge_id) do
    require Logger

    try do
      # Try to get the charge amount to calculate estimated fee
      case Stripe.Charge.retrieve(charge_id) do
        {:ok, %Stripe.Charge{amount: amount}} ->
          # amount is in cents, convert to dollars for calculation
          amount_dollars = MoneyHelper.cents_to_dollars(amount)
          calculate_estimated_fee(amount_dollars)

        {:error, reason} ->
          Logger.error("Failed to fetch charge amount for fee estimation",
            charge_id: charge_id,
            error: reason
          )

          # Return zero fee as last resort
          Money.new(0, :USD)
      end
    rescue
      error ->
        Logger.error("Exception while fetching charge amount for fee estimation",
          charge_id: charge_id,
          error: Exception.message(error)
        )

        # Return zero fee as last resort
        Money.new(0, :USD)
    end
  end

  # Helper function to calculate estimated Stripe fee (fallback only)
  defp calculate_estimated_fee(amount) do
    # 2.9% + 30¢ for domestic cards
    # amount is a Decimal from cents_to_dollars, so 30¢ = 0.30
    estimated_fee = Decimal.add(Decimal.mult(amount, Decimal.new("0.029")), Decimal.new("0.30"))
    # Return Money directly with the fee in dollars (no need to convert back to cents)
    Money.new(:USD, estimated_fee)
  end

  # Helper function to find subscription ID from Stripe subscription ID
  defp find_subscription_id_from_stripe_id(stripe_subscription_id, _user) do
    case Ysc.Subscriptions.get_subscription_by_stripe_id(stripe_subscription_id) do
      nil -> nil
      subscription -> subscription.id
    end
  end

  # Helper function to extract Stripe fee from invoice
  defp extract_stripe_fee_from_invoice(invoice) do
    # Check if fee is provided in metadata first
    metadata = invoice[:metadata] || invoice["metadata"] || %{}
    charge_id = invoice[:charge] || invoice["charge"]

    case metadata do
      %{"stripe_fee" => fee_str} ->
        case Integer.parse(fee_str) do
          # fee is already in cents
          {fee, _} -> Money.new(:USD, MoneyHelper.cents_to_dollars(fee))
          :error -> fetch_actual_stripe_fee_from_charge(charge_id)
        end

      _ ->
        fetch_actual_stripe_fee_from_charge(charge_id)
    end
  end

  # Helper function to update subscription items
  defp update_subscription_items(subscription, stripe_items) do
    # Create/update subscription items
    subscription_items =
      Subscriptions.subscription_item_structs_from_stripe_items(stripe_items, subscription)

    # Insert new items, update any items that may have changed
    Enum.each(subscription_items, fn item ->
      Ysc.Repo.insert!(item, on_conflict: :replace_all, conflict_target: [:stripe_id])
    end)

    # Delete any items that may have been removed
    item_ids = Enum.map(stripe_items, & &1.id)

    from(s in Ysc.Subscriptions.SubscriptionItem,
      where: s.subscription_id == ^subscription.id,
      where: s.stripe_id not in ^item_ids
    )
    |> Ysc.Repo.delete_all()
  end

  # Helper function to ensure customer has a default payment method after subscription creation

  # Helper function to print detailed breakdown of payments included in a payout
  defp print_payout_breakdown(payout_id, payout_amount) do
    require Logger

    Logger.info("=== PAYOUT BREAKDOWN ===",
      payout_id: payout_id,
      total_payout_amount: Money.to_string!(payout_amount)
    )

    # Get all payments that were part of this payout
    # Note: This is a simplified approach. In a real implementation, you might need to
    # correlate payments with payouts using Stripe's API or additional tracking
    recent_payments = get_recent_payments_for_payout_breakdown()

    # Group payments by type
    payments_by_type = group_payments_by_type(recent_payments)

    # Print summary for each payment type
    Enum.each(payments_by_type, fn {type, payments} ->
      total_amount = calculate_total_amount(payments)
      count = length(payments)

      Logger.info("Payment Type: #{type}",
        count: count,
        total_amount: Money.to_string!(total_amount)
      )

      # Print details for each payment
      Enum.each(payments, fn payment ->
        Logger.info("  - #{payment.payment_type_info.details}",
          payment_id: payment.id,
          amount: Money.to_string!(payment.amount),
          user: get_user_display_name(payment.user),
          date: payment.payment_date
        )
      end)
    end)

    Logger.info("=== END PAYOUT BREAKDOWN ===")
  end

  # Helper function to get recent payments for payout breakdown
  defp get_recent_payments_for_payout_breakdown do
    # Get payments from the last 7 days as a reasonable window for payout correlation
    start_date = DateTime.add(DateTime.utc_now(), -7, :day)
    end_date = DateTime.utc_now()

    Ysc.Ledgers.get_recent_payments(start_date, end_date, 100)
  end

  # Helper function to group payments by type
  defp group_payments_by_type(payments) do
    payments
    |> Enum.group_by(fn payment ->
      payment.payment_type_info.type
    end)
  end

  # Helper function to calculate total amount for a list of payments
  defp calculate_total_amount(payments) do
    payments
    |> Enum.map(fn payment -> payment.amount end)
    |> Enum.reduce(Money.new(0, :USD), fn amount, acc ->
      case Money.add(acc, amount) do
        {:ok, result} -> result
        {:error, _} -> acc
      end
    end)
  end

  # Helper function to get user display name
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

  # Helper function to extract payment method from Stripe invoice
  defp extract_payment_method_from_invoice(invoice) do
    require Logger

    # Get the charge ID from the invoice
    charge_id = invoice[:charge] || invoice["charge"]

    case charge_id do
      nil ->
        Logger.info("No charge found in invoice", invoice_id: invoice[:id] || invoice["id"])
        nil

      charge_id when is_binary(charge_id) ->
        # Retrieve the charge to get payment method details
        case Stripe.Charge.retrieve(charge_id) do
          {:ok, charge} ->
            # Get the payment method ID from the charge
            payment_method_id = charge.payment_method

            case payment_method_id do
              nil ->
                Logger.info("No payment method found in charge",
                  charge_id: charge_id,
                  invoice_id: invoice[:id] || invoice["id"]
                )

                nil

              payment_method_id when is_binary(payment_method_id) ->
                # Find the payment method in our database
                case Ysc.Payments.get_payment_method_by_provider(:stripe, payment_method_id) do
                  nil ->
                    Logger.info("Payment method not found in local database",
                      stripe_payment_method_id: payment_method_id,
                      charge_id: charge_id
                    )

                    nil

                  payment_method ->
                    Logger.info("Found payment method for invoice",
                      payment_method_id: payment_method.id,
                      stripe_payment_method_id: payment_method_id,
                      charge_id: charge_id
                    )

                    payment_method.id
                end
            end

          {:error, error} ->
            Logger.warning("Failed to retrieve charge from Stripe",
              charge_id: charge_id,
              error: error.message,
              invoice_id: invoice[:id] || invoice["id"]
            )

            nil
        end
    end
  end

  # Process refund from Stripe charge object
  defp process_refund_from_charge(%Stripe.Charge{} = charge) do
    require Logger

    # Get the payment intent ID from the charge
    payment_intent_id = charge.payment_intent

    if payment_intent_id do
      # Find the payment by external_payment_id
      payment = Ledgers.get_payment_by_external_id(payment_intent_id)

      if payment do
        # Get refund amount from charge refunds
        refund_amount =
          case charge.refunds do
            %Stripe.List{data: refunds} when is_list(refunds) ->
              # Sum all refund amounts
              total_cents =
                Enum.reduce(refunds, 0, fn refund, acc ->
                  case refund do
                    %Stripe.Refund{amount: amount} -> acc + amount
                    %{amount: amount} when is_integer(amount) -> acc + amount
                    _ -> acc
                  end
                end)

              Money.new(:USD, MoneyHelper.cents_to_dollars(total_cents))

            _ ->
              # Fallback: if we can't get refunds, try to get from charge amount
              # This is a partial fallback - ideally we should have the refund object
              Money.new(:USD, MoneyHelper.cents_to_dollars(charge.amount))
          end

        # Get refund reason from metadata or use default
        reason =
          case charge.metadata do
            %{"reason" => reason} when is_binary(reason) -> reason
            %{reason: reason} when is_binary(reason) -> reason
            _ -> "Booking cancellation refund"
          end

        # Get refund ID from the first refund
        refund_id =
          case charge.refunds do
            %Stripe.List{data: [%Stripe.Refund{id: id} | _]} -> id
            %Stripe.List{data: [%{id: id} | _]} when is_binary(id) -> id
            [%Stripe.Refund{id: id} | _] -> id
            [%{id: id} | _] when is_binary(id) -> id
            _ -> nil
          end

        # Process refund in ledger
        case Ledgers.process_refund(%{
               payment_id: payment.id,
               refund_amount: refund_amount,
               reason: reason,
               external_refund_id: refund_id
             }) do
          {:ok, {_refund_transaction, _entries}} ->
            Logger.info("Refund processed successfully in ledger",
              payment_id: payment.id,
              refund_id: refund_id,
              amount: Money.to_string!(refund_amount)
            )

            :ok

          {:error, reason} ->
            Logger.error("Failed to process refund in ledger",
              payment_id: payment.id,
              refund_id: refund_id,
              error: inspect(reason)
            )

            :ok
        end
      else
        Logger.warning("Payment not found for refund",
          payment_intent_id: payment_intent_id,
          charge_id: charge.id
        )

        :ok
      end
    else
      Logger.warning("No payment intent ID found in charge",
        charge_id: charge.id
      )

      :ok
    end
  end

  # Process refund from Stripe refund object (can be struct or map)
  defp process_refund_from_refund_object(%Stripe.Refund{} = refund) do
    # Convert struct to map for unified processing
    process_refund_from_refund_object(Map.from_struct(refund))
  end

  defp process_refund_from_refund_object(refund) when is_map(refund) do
    require Logger

    # Extract fields from refund (handles both struct and map)
    refund_id = Map.get(refund, :id) || Map.get(refund, "id")
    charge_id = Map.get(refund, :charge) || Map.get(refund, "charge")
    amount = Map.get(refund, :amount) || Map.get(refund, "amount")
    metadata = Map.get(refund, :metadata) || Map.get(refund, "metadata") || %{}

    # Get payment intent ID directly from refund object (preferred) or from charge
    payment_intent_id =
      Map.get(refund, :payment_intent) || Map.get(refund, "payment_intent")

    # If payment_intent is not directly available, try to get it from charge
    payment_intent_id =
      if is_nil(payment_intent_id) && charge_id do
        case Stripe.Charge.retrieve(charge_id, %{expand: ["payment_intent"]}) do
          {:ok, charge} ->
            charge.payment_intent

          {:error, reason} ->
            Logger.warning("Failed to retrieve charge for refund",
              charge_id: charge_id,
              refund_id: refund_id,
              error: inspect(reason)
            )

            nil
        end
      else
        payment_intent_id
      end

    if payment_intent_id do
      # Find the payment by external_payment_id
      payment = Ledgers.get_payment_by_external_id(payment_intent_id)

      if payment do
        # Convert refund amount from cents to Money
        refund_amount = Money.new(:USD, MoneyHelper.cents_to_dollars(amount))

        # Get refund reason from metadata or use default
        reason =
          case metadata do
            %{"reason" => reason} when is_binary(reason) -> reason
            %{reason: reason} when is_binary(reason) -> reason
            _ -> "Booking cancellation refund"
          end

        # Process refund in ledger
        case Ledgers.process_refund(%{
               payment_id: payment.id,
               refund_amount: refund_amount,
               reason: reason,
               external_refund_id: refund_id
             }) do
          {:ok, {_refund_transaction, _entries}} ->
            Logger.info("Refund processed successfully in ledger",
              payment_id: payment.id,
              refund_id: refund_id,
              amount: Money.to_string!(refund_amount)
            )

            :ok

          {:error, reason} ->
            Logger.error("Failed to process refund in ledger",
              payment_id: payment.id,
              refund_id: refund_id,
              error: inspect(reason)
            )

            :ok
        end
      else
        Logger.warning("Payment not found for refund",
          payment_intent_id: payment_intent_id,
          refund_id: refund_id
        )

        :ok
      end
    else
      Logger.warning("No payment intent ID found in refund",
        refund_id: refund_id,
        charge_id: charge_id
      )

      :ok
    end
  end

  # Helper function to link payments and refunds to a payout
  defp link_payout_transactions(payout, stripe_payout_id) do
    require Logger

    try do
      # Fetch balance transactions for this payout from Stripe
      # Balance transactions show all charges, refunds, and fees included in the payout
      case Stripe.BalanceTransaction.list(%{payout: stripe_payout_id, limit: 100}) do
        {:ok, %Stripe.List{data: balance_transactions}} ->
          Logger.info("Found #{length(balance_transactions)} balance transactions for payout",
            payout_id: stripe_payout_id
          )

          Enum.each(balance_transactions, fn balance_transaction ->
            link_balance_transaction_to_payout(payout, balance_transaction)
          end)

        {:error, reason} ->
          Logger.warning("Failed to fetch balance transactions for payout",
            payout_id: stripe_payout_id,
            error: inspect(reason)
          )
      end
    rescue
      error ->
        Logger.error("Exception while linking payout transactions",
          payout_id: stripe_payout_id,
          error: Exception.message(error)
        )
    end
  end

  # Helper function to link a single balance transaction to a payout
  defp link_balance_transaction_to_payout(payout, balance_transaction) do
    require Logger

    # Balance transactions can be charges, refunds, or other types
    # We need to find the corresponding payment or refund in our system
    case balance_transaction.type do
      "charge" ->
        # Find payment by charge ID (which is the payment_intent ID)
        charge_id = balance_transaction.source
        link_charge_to_payout(payout, charge_id)

      "refund" ->
        # Find refund transaction by refund ID
        refund_id = balance_transaction.source
        link_stripe_refund_to_payout(payout, refund_id)

      _ ->
        # Other types (fees, adjustments, etc.) - skip for now
        :ok
    end
  end

  # Helper function to link a charge to a payout
  defp link_charge_to_payout(payout, charge_id) do
    require Logger

    try do
      # Get the charge to find the payment intent
      case Stripe.Charge.retrieve(charge_id) do
        {:ok, charge} ->
          payment_intent_id = charge.payment_intent

          if payment_intent_id do
            # Find payment by external_payment_id (payment intent ID)
            payment = Ledgers.get_payment_by_external_id(payment_intent_id)

            if payment do
              case Ledgers.link_payment_to_payout(payout, payment) do
                {:ok, _} ->
                  Logger.info("Linked payment to payout",
                    payout_id: payout.stripe_payout_id,
                    payment_id: payment.id,
                    charge_id: charge_id
                  )

                {:error, reason} ->
                  Logger.warning("Failed to link payment to payout",
                    payout_id: payout.stripe_payout_id,
                    payment_id: payment.id,
                    error: inspect(reason)
                  )
              end
            else
              Logger.debug("Payment not found for charge",
                charge_id: charge_id,
                payment_intent_id: payment_intent_id
              )
            end
          end

        {:error, reason} ->
          Logger.warning("Failed to retrieve charge",
            charge_id: charge_id,
            error: inspect(reason)
          )
      end
    rescue
      error ->
        Logger.error("Exception while linking charge to payout",
          charge_id: charge_id,
          error: Exception.message(error)
        )
    end
  end

  # Helper function to link a Stripe refund to a payout
  defp link_stripe_refund_to_payout(payout, stripe_refund_id) do
    require Logger

    try do
      # Get the refund to find the charge/payment intent
      case Stripe.Refund.retrieve(stripe_refund_id) do
        {:ok, refund} ->
          charge_id = refund.charge

          if charge_id do
            # Get the charge to find the payment intent
            case Stripe.Charge.retrieve(charge_id) do
              {:ok, charge} ->
                payment_intent_id = charge.payment_intent

                if payment_intent_id do
                  # Find the payment
                  payment = Ledgers.get_payment_by_external_id(payment_intent_id)

                  if payment do
                    # Find the refund transaction for this payment
                    refund_transaction =
                      from(t in Ysc.Ledgers.LedgerTransaction,
                        where: t.payment_id == ^payment.id,
                        where: t.type == "refund",
                        order_by: [desc: t.inserted_at],
                        limit: 1
                      )
                      |> Ysc.Repo.one()

                    if refund_transaction do
                      case Ledgers.link_refund_to_payout(payout, refund_transaction) do
                        {:ok, _} ->
                          Logger.info("Linked refund to payout",
                            payout_id: payout.stripe_payout_id,
                            refund_transaction_id: refund_transaction.id,
                            stripe_refund_id: stripe_refund_id
                          )

                        {:error, reason} ->
                          Logger.warning("Failed to link refund to payout",
                            payout_id: payout.stripe_payout_id,
                            refund_transaction_id: refund_transaction.id,
                            error: inspect(reason)
                          )
                      end
                    else
                      Logger.debug("Refund transaction not found for payment",
                        payment_id: payment.id,
                        stripe_refund_id: stripe_refund_id
                      )
                    end
                  end
                end

              {:error, reason} ->
                Logger.warning("Failed to retrieve charge for refund",
                  charge_id: charge_id,
                  error: inspect(reason)
                )
            end
          end

        {:error, reason} ->
          Logger.warning("Failed to retrieve refund",
            stripe_refund_id: stripe_refund_id,
            error: inspect(reason)
          )
      end
    rescue
      error ->
        Logger.error("Exception while linking refund to payout",
          stripe_refund_id: stripe_refund_id,
          error: Exception.message(error)
        )
    end
  end
end
