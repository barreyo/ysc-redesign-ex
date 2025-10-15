defmodule Ysc.Stripe.WebhookHandler do
  alias Ysc.Customers
  alias Ysc.Subscriptions

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
    IO.puts("customer.subscription.created")
    IO.inspect(event)

    customer = Ysc.Accounts.get_user_from_stripe_id(event.customer)
    subscription = Subscriptions.create_subscription_from_stripe(customer, event)

    IO.inspect(subscription)

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
    IO.puts("customer.subscription.updated")
    IO.inspect(event)

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

  defp handle(_event_name, _event_object), do: :ok

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
    # Convert lists
    Enum.map(list, &convert_to_map/1)
  end

  defp convert_to_map(value), do: value

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
end
