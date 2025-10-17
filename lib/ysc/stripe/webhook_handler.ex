defmodule Ysc.Stripe.WebhookHandler do
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
      DuplicateWebhookEventError ->
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

    if !user do
      :ok
    else
      user
      |> Customers.subscriptions()
      |> Enum.each(&Subscriptions.mark_as_cancelled/1)

      :ok
    end
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

    if !subscription do
      :ok
    else
      Subscriptions.mark_as_cancelled(subscription)

      :ok
    end
  end

  defp handle("customer.subscription.updated", %Stripe.Subscription{} = event) do
    subscription = Subscriptions.get_subscription_by_stripe_id(event.id)

    if !subscription do
      nil
    else
      status = event.status

      if status == "incomplete_expired" do
        Subscriptions.delete_subscription(subscription)

        :ok
      else
        # Update subscription
        user = Ysc.Accounts.get_user_from_stripe_id(event.customer)

        subscription_changeset =
          Subscriptions.subscription_struct_from_stripe_subscription(user, event)

        case Ysc.Repo.update(subscription_changeset) do
          {:ok, updated_subscription} ->
            # Update subscription items
            update_subscription_items(updated_subscription, event.items.data)
            :ok

          {:error, _changeset} ->
            :ok
        end
      end
    end
  end

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
              amount: Money.new(MoneyHelper.cents_to_dollars(amount_paid), :USD),
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

    Logger.info("Processing Stripe payout",
      payout_id: payout[:id] || payout["id"],
      amount: payout[:amount] || payout["amount"],
      currency: payout[:currency] || payout["currency"],
      status: payout[:status] || payout["status"]
    )

    # Process the payout in the ledger
    payout_id = payout[:id] || payout["id"]
    amount_cents = payout[:amount] || payout["amount"]
    currency = (payout[:currency] || payout["currency"]) |> String.downcase() |> String.to_atom()
    description = payout[:description] || payout["description"] || "Stripe payout"

    # Convert amount from cents to Money struct
    payout_amount = Money.new(MoneyHelper.cents_to_dollars(amount_cents), currency)

    # Process the payout in the ledger
    case Ledgers.process_stripe_payout(%{
           payout_amount: payout_amount,
           stripe_payout_id: payout_id,
           description: description
         }) do
      {:ok, {_payout_payment, _transaction, _entries}} ->
        Logger.info("Stripe payout processed successfully in ledger",
          payout_id: payout_id,
          amount: Money.to_string!(payout_amount)
        )

        # Get detailed breakdown of payments included in this payout
        print_payout_breakdown(payout_id, payout_amount)

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

  defp handle(_event_name, _event_object), do: :ok

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
  defp extract_entity_type_from_payment_intent(payment_intent) do
    # Extract entity type from metadata or description
    # For membership subscriptions, check if this is related to a subscription
    case payment_intent.metadata do
      %{"entity_type" => entity_type} ->
        String.to_atom(entity_type)

      _ ->
        # Check if this payment intent is related to a subscription
        if is_subscription_payment?(payment_intent) do
          :membership
        else
          # Try to infer from description
          case payment_intent.description do
            desc when is_binary(desc) ->
              cond do
                String.contains?(String.downcase(desc), "subscription") -> :membership
                String.contains?(String.downcase(desc), "membership") -> :membership
                String.contains?(String.downcase(desc), "event") -> :event
                String.contains?(String.downcase(desc), "booking") -> :booking
                String.contains?(String.downcase(desc), "donation") -> :donation
                # Default to membership for subscription-related payments
                true -> :membership
              end

            _ ->
              # Default to membership for subscription-related payments
              :membership
          end
        end
    end
  end

  defp extract_entity_id_from_payment_intent(payment_intent, user) do
    # Extract entity ID from metadata
    case payment_intent.metadata do
      %{"entity_id" => entity_id} ->
        entity_id

      _ ->
        # For membership subscriptions, try to find the subscription ID
        if is_subscription_payment?(payment_intent) do
          find_subscription_id_for_payment(payment_intent, user)
        else
          nil
        end
    end
  end

  defp extract_stripe_fee_from_payment_intent(payment_intent) do
    # Check if fee is provided in metadata first
    case payment_intent.metadata do
      %{"stripe_fee" => fee_str} ->
        case Integer.parse(fee_str) do
          # fee is already in cents
          {fee, _} -> Money.new(MoneyHelper.cents_to_dollars(fee), :USD)
          :error -> fetch_actual_stripe_fee_from_payment_intent(payment_intent)
        end

      _ ->
        fetch_actual_stripe_fee_from_payment_intent(payment_intent)
    end
  end

  # Helper function to fetch actual Stripe fee from payment intent
  defp fetch_actual_stripe_fee_from_payment_intent(payment_intent) do
    require Logger

    # Try to get the latest charge from the payment intent
    case payment_intent.latest_charge do
      charge_id when is_binary(charge_id) ->
        fetch_actual_stripe_fee_from_charge(charge_id)

      nil ->
        Logger.warning("No latest charge found for payment intent",
          payment_intent_id: payment_intent.id
        )

        # Fallback to estimated fee based on payment intent amount
        amount_dollars = MoneyHelper.cents_to_dollars(payment_intent.amount)
        calculate_estimated_fee(amount_dollars)
    end
  end

  # Helper function to fetch actual Stripe fee from charge
  defp fetch_actual_stripe_fee_from_charge(charge_id) when is_binary(charge_id) do
    require Logger

    try do
      # Fetch the charge with expanded balance transaction to get actual fees
      case Stripe.Charge.retrieve(charge_id, expand: ["balance_transaction"]) do
        {:ok, %Stripe.Charge{balance_transaction: %Stripe.BalanceTransaction{fee: fee}}} ->
          # fee is already in cents
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
    # Convert to cents for Money.new to avoid precision issues
    estimated_fee_cents =
      Decimal.mult(estimated_fee, Decimal.new("100")) |> Decimal.round(0) |> Decimal.to_integer()

    Money.new(MoneyHelper.cents_to_dollars(estimated_fee_cents), :USD)
  end

  defp extract_description_from_payment_intent(payment_intent) do
    payment_intent.description || "Payment via Stripe"
  end

  # Helper function to determine if a payment intent is related to a subscription
  defp is_subscription_payment?(payment_intent) do
    # Check if the payment intent has subscription-related metadata
    case payment_intent.metadata do
      %{"subscription_id" => _} ->
        true

      %{"entity_type" => "membership"} ->
        true

      _ ->
        # Check if the description indicates a subscription
        case payment_intent.description do
          desc when is_binary(desc) ->
            String.contains?(String.downcase(desc), "subscription") or
              String.contains?(String.downcase(desc), "membership") or
              String.contains?(String.downcase(desc), "single") or
              String.contains?(String.downcase(desc), "family")

          _ ->
            false
        end
    end
  end

  # Helper function to find the subscription ID for a payment intent
  defp find_subscription_id_for_payment(payment_intent, _user) do
    # Try to find the subscription from metadata first
    case payment_intent.metadata do
      %{"subscription_id" => subscription_id} ->
        subscription_id

      _ ->
        # For now, return nil if no subscription ID in metadata
        # In a more sophisticated implementation, you could query for the user's active subscription
        nil
    end
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
          {fee, _} -> Money.new(MoneyHelper.cents_to_dollars(fee), :USD)
          :error -> fetch_actual_stripe_fee_from_charge(charge_id)
        end

      _ ->
        fetch_actual_stripe_fee_from_charge(charge_id)
    end
  end

  # Helper function to update subscription items
  defp update_subscription_items(subscription, stripe_items) do
    import Ecto.Query, only: [from: 2]

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
  defp ensure_customer_has_default_payment_method(user) do
    require Logger

    try do
      # Check if customer has a default payment method locally
      case Ysc.Payments.get_default_payment_method(user) do
        nil ->
          # No local default payment method, try to set one from available payment methods
          payment_methods = Ysc.Payments.list_payment_methods(user)

          if length(payment_methods) > 0 do
            # Set the first available payment method as default
            first_payment_method = Enum.min_by(payment_methods, & &1.inserted_at)

            case Ysc.Payments.set_default_payment_method(user, first_payment_method) do
              {:ok, _} ->
                Logger.info("Set default payment method for customer after subscription creation",
                  user_id: user.id,
                  payment_method_id: first_payment_method.id
                )

              {:error, _} ->
                Logger.warning(
                  "Failed to set default payment method for customer after subscription creation",
                  user_id: user.id,
                  payment_method_id: first_payment_method.id
                )
            end
          else
            Logger.info("No payment methods available to set as default for customer",
              user_id: user.id
            )
          end

        _existing_default ->
          # Customer already has a default payment method, no action needed
          Logger.debug("Customer already has default payment method", user_id: user.id)
      end
    rescue
      error ->
        Logger.error(
          "Error ensuring customer has default payment method after subscription creation",
          user_id: user.id,
          error: Exception.message(error)
        )
    end
  end

  # Helper function to update customer's default payment method from Stripe using new structure
  defp update_customer_default_payment_method_from_stripe(user) do
    require Logger

    try do
      # Get the default payment method from Stripe
      case Customers.default_payment_method(user) do
        nil ->
          # No default payment method in Stripe
          case Ysc.Payments.list_payment_methods(user) do
            [] ->
              Logger.info("No payment methods found for customer", user_id: user.id)

            payment_methods ->
              # Only unset default payment methods if the customer has no payment methods in Stripe
              # This prevents unsetting defaults during subscription creation when Stripe might temporarily
              # not have a default payment method set
              stripe_payment_methods = Customers.payment_methods(user)

              if length(stripe_payment_methods) == 0 do
                # Customer truly has no payment methods in Stripe, safe to unset local defaults
                Enum.each(payment_methods, fn pm ->
                  if pm.is_default do
                    Ysc.Payments.update_payment_method(pm, %{is_default: false})
                  end
                end)

                Logger.info(
                  "Unset default payment method for customer (no Stripe payment methods)",
                  user_id: user.id
                )
              else
                # Customer has payment methods in Stripe but no default set
                # This might be temporary during subscription creation, so preserve local default
                Logger.info(
                  "Customer has Stripe payment methods but no default set, preserving local default",
                  user_id: user.id,
                  stripe_payment_method_count: length(stripe_payment_methods)
                )
              end
          end

        stripe_payment_method ->
          # Find the corresponding payment method in our database
          case Ysc.Payments.get_payment_method_by_provider(:stripe, stripe_payment_method.id) do
            nil ->
              Logger.warning("Default payment method from Stripe not found in local database",
                user_id: user.id,
                stripe_payment_method_id: stripe_payment_method.id
              )

            local_payment_method ->
              # Set this payment method as default
              case Ysc.Payments.set_default_payment_method(user, local_payment_method) do
                {:ok, _} ->
                  Logger.info("Updated default payment method for customer",
                    user_id: user.id,
                    payment_method_id: local_payment_method.id
                  )

                {:error, _} ->
                  Logger.warning("Failed to update default payment method for customer",
                    user_id: user.id,
                    payment_method_id: local_payment_method.id
                  )
              end
          end
      end
    rescue
      error ->
        Logger.error("Error updating customer default payment method from Stripe",
          user_id: user.id,
          error: Exception.message(error)
        )
    end
  end

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
end
