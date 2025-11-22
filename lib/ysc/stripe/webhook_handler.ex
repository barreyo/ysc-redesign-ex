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

  # Maximum age for webhook events (5 minutes in seconds)
  @webhook_max_age_seconds 300

  def handle_event(event) do
    require Logger
    Logger.info("Processing Stripe webhook event", event_id: event.id, event_type: event.type)

    # Check for replay attacks - reject webhooks older than 5 minutes
    case check_webhook_age(event) do
      :ok ->
        process_webhook(event)

      {:error, :webhook_too_old} = error ->
        Logger.warning("Rejecting old webhook event (possible replay attack)",
          event_id: event.id,
          event_type: event.type,
          event_created: event.created,
          age_seconds: DateTime.diff(DateTime.utc_now(), DateTime.from_unix!(event.created))
        )

        error
    end
  end

  # Check if webhook is within acceptable age
  defp check_webhook_age(event) do
    event_timestamp = DateTime.from_unix!(event.created)
    current_time = DateTime.utc_now()
    age_seconds = DateTime.diff(current_time, event_timestamp)

    if age_seconds > @webhook_max_age_seconds do
      {:error, :webhook_too_old}
    else
      :ok
    end
  end

  # Process webhook after age validation
  defp process_webhook(event) do
    require Logger

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
        # Build update attrs from Stripe subscription
        attrs = %{
          stripe_status: event.status,
          start_date: event.start_date && DateTime.from_unix!(event.start_date),
          current_period_start:
            event.current_period_start && DateTime.from_unix!(event.current_period_start),
          current_period_end:
            event.current_period_end && DateTime.from_unix!(event.current_period_end),
          trial_ends_at: event.trial_end && DateTime.from_unix!(event.trial_end),
          ends_at: event.ended_at && DateTime.from_unix!(event.ended_at)
        }

        # Add cancellation info if present
        attrs =
          if event.cancel_at do
            Map.put(attrs, :ends_at, DateTime.from_unix!(event.cancel_at))
          else
            attrs
          end

        case Subscriptions.update_subscription(subscription, attrs) do
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
      metadata: invoice.metadata,
      billing_reason: Map.get(invoice, :billing_reason)
    }

    handle("invoice.payment_succeeded", invoice_map)
  end

  defp handle("invoice.payment_succeeded", invoice) when is_map(invoice) do
    require Logger

    # This webhook is specifically for subscription payments
    # It's more reliable than payment_intent.succeeded for subscription billing
    # Handle both atom and string keys for compatibility
    subscription_id = resolve_subscription_id(invoice)

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
            # Use find_or_create_subscription_reference to handle race condition
            # where invoice arrives before subscription.created webhook
            entity_id = find_or_create_subscription_reference(subscription_id, user)

            amount_paid = invoice[:amount_paid] || invoice["amount_paid"]
            description = invoice[:description] || invoice["description"]
            number = invoice[:number] || invoice["number"]

            payment_attrs = %{
              user_id: user.id,
              amount: Money.new(MoneyHelper.cents_to_dollars(amount_paid), :USD),
              entity_type: :membership,
              entity_id: entity_id,
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
                  subscription_id: subscription_id,
                  entity_id: entity_id
                )

                :ok

              {:error, reason} ->
                Logger.error("Failed to process subscription payment in ledger",
                  invoice_id: invoice_id,
                  user_id: user.id,
                  subscription_id: subscription_id,
                  error: reason
                )

                # Raise error to mark webhook as failed
                raise "Failed to process payment: #{inspect(reason)}"
            end
          end
        else
          Logger.warning("No user found for invoice payment",
            invoice_id: invoice_id,
            customer_id: customer_id
          )

          # Raise error to mark webhook as failed - missing customer is a critical error
          raise "No user found for customer_id: #{customer_id}"
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

    Logger.info("Charge refunded event received",
      charge_id: charge.id,
      payment_intent_id: charge.payment_intent
    )

    # Note: We prefer to handle refunds via the refund.created webhook
    # which fires for each individual refund. This event can contain
    # multiple refunds, making it harder to track individual refund IDs.
    # However, we'll process it as a fallback in case refund.created is missed.

    # Process each refund individually to ensure proper idempotency
    case charge.refunds do
      %Stripe.List{data: refunds} when is_list(refunds) and length(refunds) > 0 ->
        Enum.each(refunds, fn refund ->
          result = process_refund_from_refund_object(refund)

          case result do
            {:error, {:already_processed, _, _}} ->
              Logger.debug("Refund already processed (from charge.refunded event)",
                refund_id: Map.get(refund, :id),
                charge_id: charge.id
              )

            _ ->
              :ok
          end
        end)

      _ ->
        Logger.warning("No refunds data in charge.refunded event",
          charge_id: charge.id
        )
    end

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
    result = process_refund_from_refund_object(refund)

    # Handle idempotency case
    case result do
      {:error, {:already_processed, _, _}} ->
        Logger.info("Refund already processed, skipping (idempotency)",
          refund_id: refund.id,
          charge_id: refund.charge
        )

      _ ->
        :ok
    end

    :ok
  end

  defp handle("refund.created", refund) when is_map(refund) do
    require Logger

    refund_id = refund[:id] || refund["id"]
    charge_id = refund[:charge] || refund["charge"]

    Logger.info("Refund created (map)",
      refund_id: refund_id,
      charge_id: charge_id,
      amount: refund[:amount] || refund["amount"]
    )

    # Process refund in ledger
    result = process_refund_from_refund_object(refund)

    # Handle idempotency case
    case result do
      {:error, {:already_processed, _, _}} ->
        Logger.info("Refund already processed, skipping (idempotency)",
          refund_id: refund_id,
          charge_id: charge_id
        )

      _ ->
        :ok
    end

    :ok
  end

  defp handle("refund.updated", %Stripe.Refund{} = refund) do
    require Logger

    Logger.info("Refund updated",
      refund_id: refund.id,
      charge_id: refund.charge,
      amount: refund.amount,
      status: refund.status
    )

    # You could add logic here to update refund status in ledger
    :ok
  end

  defp handle("refund.updated", refund) when is_map(refund) do
    require Logger

    refund_id = refund[:id] || refund["id"]
    charge_id = refund[:charge] || refund["charge"]

    Logger.info("Refund updated (map)",
      refund_id: refund_id,
      charge_id: charge_id,
      amount: refund[:amount] || refund["amount"],
      status: refund[:status] || refund["status"]
    )

    # You could add logic here to update refund status in ledger
    :ok
  end

  defp handle(_event_name, _event_object), do: :ok

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
    payout_amount = Money.new(MoneyHelper.cents_to_dollars(amount_cents), currency)

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

        # After linking is complete, check if we should enqueue QuickBooks sync
        # Only sync if all linked payments/refunds are already synced
        enqueue_quickbooks_sync_payout_if_ready(payout)

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

  @doc """
  Fetches the actual Stripe fee from a charge by retrieving the balance transaction.

  This is the preferred method for getting accurate fee information.
  Falls back to estimated fee calculation if the charge cannot be retrieved.

  ## Parameters:
  - `charge_id`: Stripe charge ID

  ## Returns:
  - `%Money{}` - The Stripe fee amount
  """
  def fetch_actual_stripe_fee_from_charge(charge_id) when is_binary(charge_id) do
    require Logger

    try do
      # Fetch the charge with expanded balance transaction to get actual fees
      case Stripe.Charge.retrieve(charge_id, expand: ["balance_transaction"]) do
        {:ok, %Stripe.Charge{balance_transaction: %Stripe.BalanceTransaction{fee: fee}}} ->
          # fee is already in cents, convert to dollars
          # Log the fee for debugging
          Logger.info("Extracted Stripe fee from balance transaction",
            charge_id: charge_id,
            fee_cents: fee,
            fee_dollars: MoneyHelper.cents_to_dollars(fee)
          )

          Money.new(MoneyHelper.cents_to_dollars(fee), :USD)

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

  def fetch_actual_stripe_fee_from_charge(nil) do
    require Logger
    Logger.warning("No charge ID provided for fee calculation")
    # Return zero fee if no charge ID
    Money.new(0, :USD)
  end

  @doc """
  Calculates an estimated Stripe fee when we can't fetch the actual fee.

  Uses the charge amount to estimate: 2.9% + $0.30

  ## Parameters:
  - `charge_id`: Stripe charge ID

  ## Returns:
  - `%Money{}` - The estimated Stripe fee amount
  """
  def calculate_estimated_fee_from_charge_amount(charge_id) do
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

  @doc """
  Calculates an estimated Stripe fee based on payment amount.

  Formula: 2.9% + $0.30

  ## Parameters:
  - `amount`: Payment amount as a Decimal (in dollars)

  ## Returns:
  - `%Money{}` - The estimated Stripe fee amount
  """
  def calculate_estimated_fee(amount) do
    # 2.9% + 30¢ for domestic cards
    # amount is a Decimal from cents_to_dollars, so 30¢ = 0.30
    estimated_fee = Decimal.add(Decimal.mult(amount, Decimal.new("0.029")), Decimal.new("0.30"))
    # Return Money directly with the fee in dollars (no need to convert back to cents)
    Money.new(estimated_fee, :USD)
  end

  # Helper function to resolve subscription ID from invoice
  # Sometimes the initial subscription invoice has subscription: null but billing_reason: subscription_create
  defp resolve_subscription_id(invoice) do
    subscription_id = invoice[:subscription] || invoice["subscription"]

    if subscription_id do
      subscription_id
    else
      billing_reason = invoice[:billing_reason] || invoice["billing_reason"]
      customer_id = invoice[:customer] || invoice["customer"]

      if billing_reason == "subscription_create" && customer_id do
        require Logger

        Logger.info("Subscription ID missing in invoice, attempting to resolve from customer",
          customer_id: customer_id,
          billing_reason: billing_reason
        )

        user = Ysc.Accounts.get_user_from_stripe_id(customer_id)

        if user do
          case Ysc.Subscriptions.list_subscriptions(user) do
            [] ->
              Logger.warning("No subscriptions found for user when resolving invoice",
                user_id: user.id
              )

              nil

            subscriptions ->
              # Get the most recently created subscription
              # We sort by inserted_at to find the one we just created
              subscription =
                subscriptions
                |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
                |> List.first()

              if subscription do
                Logger.info("Resolved subscription ID from user subscriptions",
                  resolved_subscription_id: subscription.stripe_id
                )

                subscription.stripe_id
              else
                nil
              end
          end
        else
          Logger.warning("User not found when resolving invoice subscription",
            stripe_customer_id: customer_id
          )

          nil
        end
      else
        nil
      end
    end
  end

  # Helper function to find or create subscription reference from Stripe
  # This handles the race condition where invoice.payment_succeeded arrives before customer.subscription.created
  defp find_or_create_subscription_reference(stripe_subscription_id, user) do
    require Logger

    # Try to find existing subscription
    case Ysc.Subscriptions.get_subscription_by_stripe_id(stripe_subscription_id) do
      nil ->
        # Subscription doesn't exist locally yet
        # Fetch from Stripe and create it to ensure proper entity_id linkage
        Logger.info(
          "Subscription not found locally, fetching from Stripe to prevent race condition",
          stripe_subscription_id: stripe_subscription_id,
          user_id: user.id
        )

        case Stripe.Subscription.retrieve(stripe_subscription_id) do
          {:ok, stripe_subscription} ->
            case Subscriptions.create_subscription_from_stripe(user, stripe_subscription) do
              {:ok, subscription} ->
                Logger.info("Created subscription from Stripe before processing payment",
                  subscription_id: subscription.id,
                  stripe_subscription_id: stripe_subscription_id,
                  user_id: user.id
                )

                subscription.id

              {:error, reason} ->
                Logger.error("Failed to create subscription from Stripe",
                  stripe_subscription_id: stripe_subscription_id,
                  user_id: user.id,
                  error: inspect(reason)
                )

                nil
            end

          {:error, reason} ->
            Logger.error("Failed to fetch subscription from Stripe",
              stripe_subscription_id: stripe_subscription_id,
              user_id: user.id,
              error: inspect(reason)
            )

            nil
        end

      subscription ->
        subscription.id
    end
  end

  @doc """
  Extracts Stripe fee from an invoice.

  First checks invoice metadata for a fee, then falls back to fetching from the charge.

  ## Parameters:
  - `invoice`: Stripe invoice (map or struct)

  ## Returns:
  - `%Money{}` - The Stripe fee amount
  """
  def extract_stripe_fee_from_invoice(invoice) do
    require Logger

    # Check if fee is provided in metadata first
    metadata = invoice[:metadata] || invoice["metadata"] || %{}
    charge_id = invoice[:charge] || invoice["charge"]

    case metadata do
      %{"stripe_fee" => fee_str} ->
        # Try to parse as integer (cents) first
        case Integer.parse(fee_str) do
          {fee, _} ->
            # If fee seems too large (likely already in dollars), treat as dollars
            # A fee over $1000 would be unusual for most payments
            if fee > 100_000 do
              Logger.warning("Fee in metadata seems unusually large, treating as dollars",
                fee_value: fee,
                charge_id: charge_id
              )

              # Treat as dollars (already converted)
              Money.new(Decimal.new(fee_str), :USD)
            else
              # fee is in cents, convert to dollars
              Money.new(MoneyHelper.cents_to_dollars(fee), :USD)
            end

          :error ->
            # Try parsing as decimal (might be in dollars already)
            case Decimal.parse(fee_str) do
              {decimal, _} ->
                Logger.info("Fee in metadata parsed as decimal (treating as dollars)",
                  fee_value: fee_str,
                  charge_id: charge_id
                )

                Money.new(decimal, :USD)

              :error ->
                Logger.warning("Could not parse fee from metadata, fetching from charge",
                  fee_value: fee_str,
                  charge_id: charge_id
                )

                fetch_actual_stripe_fee_from_charge(charge_id)
            end
        end

      _ ->
        fetch_actual_stripe_fee_from_charge(charge_id)
    end
  end

  @doc """
  Extracts Stripe fee from a payment intent.

  Retrieves the charge from the payment intent and fetches the actual fee from the balance transaction.
  Falls back to estimated fee if the charge cannot be retrieved.

  ## Parameters:
  - `payment_intent`: Stripe payment intent (struct or map with :id or "id")

  ## Returns:
  - `%Money{}` - The Stripe fee amount
  """
  def extract_stripe_fee_from_payment_intent(payment_intent) do
    require Logger

    payment_intent_id = get_payment_intent_id(payment_intent)

    # Try to get the charge from the payment intent
    case get_charge_from_payment_intent(payment_intent) do
      {:ok, %{id: charge_id}} when is_binary(charge_id) ->
        # We have a charge ID, fetch actual fee
        fetch_actual_stripe_fee_from_charge(charge_id)

      {:ok, charge} when is_map(charge) ->
        # We have a charge struct, extract the ID
        charge_id = Map.get(charge, :id) || Map.get(charge, "id")

        if charge_id do
          fetch_actual_stripe_fee_from_charge(charge_id)
        else
          # No charge ID found, estimate from payment intent
          estimate_fee_from_payment_intent(payment_intent)
        end

      {:error, _reason} ->
        # Fallback: try to retrieve payment intent with charges expanded
        case retrieve_payment_intent_with_charges(payment_intent_id) do
          {:ok, payment_intent_with_charges} ->
            case get_charge_from_payment_intent(payment_intent_with_charges) do
              {:ok, %{id: charge_id}} when is_binary(charge_id) ->
                fetch_actual_stripe_fee_from_charge(charge_id)

              {:ok, charge} when is_map(charge) ->
                charge_id = Map.get(charge, :id) || Map.get(charge, "id")

                if charge_id do
                  fetch_actual_stripe_fee_from_charge(charge_id)
                else
                  estimate_fee_from_payment_intent(payment_intent)
                end

              {:error, _} ->
                # Final fallback: estimate from payment intent amount
                estimate_fee_from_payment_intent(payment_intent)
            end

          {:error, _} ->
            # Fallback to estimated fee
            estimate_fee_from_payment_intent(payment_intent)
        end
    end
  end

  # Helper to get payment intent ID from struct or map
  defp get_payment_intent_id(%{id: id}) when is_binary(id), do: id
  defp get_payment_intent_id(%{"id" => id}) when is_binary(id), do: id
  defp get_payment_intent_id(_), do: nil

  # Helper to get charge from payment intent
  defp get_charge_from_payment_intent(%{charges: %Stripe.List{data: [charge | _]}})
       when is_map(charge),
       do: {:ok, charge}

  defp get_charge_from_payment_intent(%{"charges" => %{"data" => [charge | _]}})
       when is_map(charge),
       do: {:ok, charge}

  defp get_charge_from_payment_intent(%{latest_charge: charge_id}) when is_binary(charge_id),
    do: {:ok, %{id: charge_id}}

  defp get_charge_from_payment_intent(%{"latest_charge" => charge_id}) when is_binary(charge_id),
    do: {:ok, %{id: charge_id}}

  defp get_charge_from_payment_intent(_), do: {:error, :no_charge_found}

  # Helper to retrieve payment intent with charges expanded
  defp retrieve_payment_intent_with_charges(nil), do: {:error, :no_payment_intent_id}

  defp retrieve_payment_intent_with_charges(payment_intent_id) do
    case Stripe.PaymentIntent.retrieve(payment_intent_id, %{
           expand: ["charges.data.balance_transaction"]
         }) do
      {:ok, payment_intent} -> {:ok, payment_intent}
      {:error, reason} -> {:error, reason}
    end
  end

  # Helper to estimate fee from payment intent amount
  defp estimate_fee_from_payment_intent(payment_intent) do
    require Logger

    amount_cents = get_payment_intent_amount(payment_intent)

    if amount_cents do
      amount_dollars = MoneyHelper.cents_to_dollars(amount_cents)
      calculate_estimated_fee(amount_dollars)
    else
      Logger.warning("Could not determine payment intent amount for fee estimation")
      Money.new(0, :USD)
    end
  end

  # Helper to get amount from payment intent
  defp get_payment_intent_amount(%{amount: amount}) when is_integer(amount), do: amount
  defp get_payment_intent_amount(%{"amount" => amount}) when is_integer(amount), do: amount
  defp get_payment_intent_amount(_), do: nil

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
        # Convert refund amount from cents to dollars
        refund_amount = Money.new(MoneyHelper.cents_to_dollars(amount), :USD)

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
          {:ok, {_refund, _refund_transaction, _entries}} ->
            Logger.info("Refund processed successfully in ledger",
              payment_id: payment.id,
              refund_id: refund_id,
              amount: Money.to_string!(refund_amount)
            )

            :ok

          {:error, {:already_processed, refund, refund_transaction}} ->
            # Return the error tuple so caller can handle idempotency
            {:error, {:already_processed, refund, refund_transaction}}

          {:error, reason} ->
            Logger.error("Failed to process refund in ledger",
              payment_id: payment.id,
              refund_id: refund_id,
              error: inspect(reason)
            )

            {:error, reason}
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
      # Note: Using apply to avoid compile-time warning about undefined function
      result =
        if Code.ensure_loaded(Stripe.BalanceTransaction) &&
             function_exported?(Stripe.BalanceTransaction, :list, 1) do
          apply(Stripe.BalanceTransaction, :list, [%{payout: stripe_payout_id, limit: 100}])
        else
          {:error, :not_available}
        end

      case result do
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
                    # Find the Refund by external_refund_id
                    refund = Ledgers.get_refund_by_external_id(stripe_refund_id)

                    if refund do
                      case Ledgers.link_refund_to_payout(payout, refund) do
                        {:ok, _} ->
                          Logger.info("Linked refund to payout",
                            payout_id: payout.stripe_payout_id,
                            refund_id: refund.id,
                            stripe_refund_id: stripe_refund_id
                          )

                        {:error, reason} ->
                          Logger.warning("Failed to link refund to payout",
                            payout_id: payout.stripe_payout_id,
                            refund_id: refund.id,
                            stripe_refund_id: stripe_refund_id,
                            error: inspect(reason)
                          )
                      end
                    else
                      Logger.debug("Refund not found for Stripe refund ID",
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

  # Helper function to enqueue QuickBooks sync for payout only if all linked payments/refunds are synced
  defp enqueue_quickbooks_sync_payout_if_ready(%Ledgers.Payout{} = payout) do
    require Logger

    # Reload payout with payments and refunds
    payout = Ledgers.get_payout!(payout.id)

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

    if all_payments_synced && all_refunds_synced &&
         (length(payout.payments) > 0 || length(payout.refunds) > 0) do
      Logger.info("All payments and refunds synced, enqueueing QuickBooks sync for payout",
        payout_id: payout.id,
        payments_count: length(payout.payments),
        refunds_count: length(payout.refunds)
      )

      # Mark payout as pending sync
      payout
      |> Ledgers.Payout.changeset(%{quickbooks_sync_status: "pending"})
      |> Ysc.Repo.update()

      # Enqueue sync job
      %{payout_id: to_string(payout.id)}
      |> YscWeb.Workers.QuickbooksSyncPayoutWorker.new()
      |> Oban.insert()

      :ok
    else
      unsynced_payments = Enum.count(payout.payments, &(&1.quickbooks_sync_status != "synced"))
      unsynced_refunds = Enum.count(payout.refunds, &(&1.quickbooks_sync_status != "synced"))

      Logger.info("Payout not ready for QuickBooks sync - waiting for payments/refunds to sync",
        payout_id: payout.id,
        unsynced_payments: unsynced_payments,
        unsynced_refunds: unsynced_refunds,
        total_payments: length(payout.payments),
        total_refunds: length(payout.refunds)
      )

      :ok
    end
  rescue
    error ->
      require Logger

      Logger.error("Failed to check if payout is ready for QuickBooks sync",
        payout_id: payout.id,
        error: inspect(error)
      )

      :ok
  end
end
