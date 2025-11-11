defmodule Ysc.Tickets.StripeService do
  @moduledoc """
  Service for handling Stripe payments for ticket orders.

  This module provides:
  - Creating payment intents for ticket orders
  - Processing successful payments
  - Handling payment failures and timeouts
  - Integration with the ledger system
  """

  alias Ysc.Tickets
  alias Ysc.Ledgers

  @doc """
  Creates a Stripe payment intent for a ticket order.

  ## Parameters:
  - `ticket_order`: The ticket order to create payment for
  - `customer_id`: Stripe customer ID (optional)
  - `payment_method_id`: Stripe payment method ID (optional)

  ## Returns:
  - `{:ok, %Stripe.PaymentIntent{}}` on success
  - `{:error, reason}` on failure
  """
  def create_payment_intent(ticket_order, opts \\ []) do
    customer_id = Keyword.get(opts, :customer_id)
    payment_method_id = Keyword.get(opts, :payment_method_id)

    amount_cents = money_to_cents(ticket_order.total_amount)

    payment_intent_params = %{
      amount: amount_cents,
      currency: "usd",
      metadata: %{
        ticket_order_id: ticket_order.id,
        ticket_order_reference: ticket_order.reference_id,
        event_id: ticket_order.event_id,
        user_id: ticket_order.user_id
      },
      description: "Event tickets - Order #{ticket_order.reference_id}",
      automatic_payment_methods: %{
        enabled: true
      }
    }

    # Add customer if provided
    payment_intent_params =
      if customer_id do
        Map.put(payment_intent_params, :customer, customer_id)
      else
        payment_intent_params
      end

    # Add payment method if provided
    payment_intent_params =
      if payment_method_id do
        Map.put(payment_intent_params, :payment_method, payment_method_id)
      else
        payment_intent_params
      end

    case Stripe.PaymentIntent.create(payment_intent_params) do
      {:ok, payment_intent} ->
        # Update the ticket order with the payment intent ID
        case Tickets.update_payment_intent(ticket_order, payment_intent.id) do
          {:ok, _updated_order} ->
            {:ok, payment_intent}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, %Stripe.Error{} = error} ->
        {:error, error.message}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Processes a successful payment intent and completes the ticket order.

  ## Parameters:
  - `payment_intent_id`: The Stripe payment intent ID

  ## Returns:
  - `{:ok, %TicketOrder{}}` on success
  - `{:error, reason}` on failure
  """
  def process_successful_payment(payment_intent_id) do
    with {:ok, payment_intent} <- Stripe.PaymentIntent.retrieve(payment_intent_id, %{}),
         {:ok, ticket_order} <- get_ticket_order_from_payment_intent(payment_intent),
         :ok <- validate_payment_intent(payment_intent, ticket_order) do
      Tickets.process_ticket_order_payment(ticket_order, payment_intent_id)
    end
  end

  @doc """
  Handles a failed payment intent and cancels the ticket order.

  ## Parameters:
  - `payment_intent_id`: The Stripe payment intent ID
  - `failure_reason`: Reason for payment failure

  ## Returns:
  - `{:ok, %TicketOrder{}}` on success
  - `{:error, reason}` on failure
  """
  def handle_failed_payment(payment_intent_id, failure_reason \\ "Payment failed") do
    with {:ok, payment_intent} <- Stripe.PaymentIntent.retrieve(payment_intent_id, %{}),
         {:ok, ticket_order} <- get_ticket_order_from_payment_intent(payment_intent) do
      Tickets.cancel_ticket_order(ticket_order, failure_reason)
    end
  end

  @doc """
  Creates a customer in Stripe for a user if they don't already have one.

  ## Parameters:
  - `user`: The user to create a customer for

  ## Returns:
  - `{:ok, customer_id}` on success
  - `{:error, reason}` on failure
  """
  def ensure_stripe_customer(user) do
    case get_stripe_customer_id(user) do
      nil ->
        create_stripe_customer(user)

      customer_id ->
        {:ok, customer_id}
    end
  end

  @doc """
  Gets the Stripe customer ID for a user.
  """
  def get_stripe_customer_id(_user) do
    # This would typically be stored in the user record or a separate table
    # For now, we'll return nil and create a new customer each time
    nil
  end

  ## Private Functions

  defp get_ticket_order_from_payment_intent(payment_intent) do
    ticket_order_id = payment_intent.metadata["ticket_order_id"]

    if ticket_order_id do
      case Tickets.get_ticket_order(ticket_order_id) do
        nil -> {:error, :ticket_order_not_found}
        ticket_order -> {:ok, ticket_order}
      end
    else
      {:error, :no_ticket_order_metadata}
    end
  end

  defp validate_payment_intent(payment_intent, ticket_order) do
    expected_amount = money_to_cents(ticket_order.total_amount)

    cond do
      payment_intent.amount != expected_amount ->
        {:error, :amount_mismatch}

      payment_intent.status != "succeeded" ->
        {:error, :payment_not_succeeded}

      true ->
        :ok
    end
  end

  @doc false
  defp process_ticket_order_payment(ticket_order, payment_intent) do
    with {:ok, {payment, _transaction, _entries}} <-
           process_ledger_payment(ticket_order, payment_intent),
         {:ok, completed_order} <- Tickets.complete_ticket_order(ticket_order, payment.id),
         :ok <- confirm_tickets(completed_order.tickets) do
      {:ok, completed_order}
    end
  end

  @doc false
  defp process_ledger_payment(ticket_order, payment_intent) do
    # Extract and sync payment method before creating payment
    payment_method_id = extract_and_sync_payment_method(payment_intent, ticket_order.user_id)

    Ledgers.process_payment(%{
      user_id: ticket_order.user_id,
      amount: ticket_order.total_amount,
      entity_type: :event,
      entity_id: ticket_order.event_id,
      external_payment_id: payment_intent.id,
      stripe_fee: extract_stripe_fee(payment_intent),
      description: "Event tickets - Order #{ticket_order.reference_id}",
      property: nil,
      payment_method_id: payment_method_id
    })
  end

  @doc false
  defp extract_and_sync_payment_method(payment_intent, user_id) do
    require Logger

    case payment_intent.payment_method do
      nil ->
        Logger.info("No payment method found in payment intent",
          payment_intent_id: payment_intent.id
        )

        nil

      payment_method_id when is_binary(payment_method_id) ->
        # Retrieve the full payment method from Stripe
        case Stripe.PaymentMethod.retrieve(payment_method_id) do
          {:ok, stripe_payment_method} ->
            # Get the user to sync the payment method
            user = Ysc.Accounts.get_user!(user_id)

            # Sync the payment method to our database
            case Ysc.Payments.sync_payment_method_from_stripe(user, stripe_payment_method) do
              {:ok, payment_method} ->
                Logger.info("Successfully synced payment method for ticket payment",
                  payment_method_id: payment_method.id,
                  stripe_payment_method_id: payment_method_id,
                  user_id: user_id
                )

                payment_method.id

              {:error, reason} ->
                Logger.warning("Failed to sync payment method for ticket payment",
                  stripe_payment_method_id: payment_method_id,
                  user_id: user_id,
                  error: inspect(reason)
                )

                nil
            end

          {:error, error} ->
            Logger.warning("Failed to retrieve payment method from Stripe",
              payment_method_id: payment_method_id,
              payment_intent_id: payment_intent.id,
              error: error.message
            )

            nil
        end

      _ ->
        nil
    end
  end

  @doc false
  defp extract_stripe_fee(payment_intent) do
    # Get the actual Stripe fee from the charge
    case get_charge_from_payment_intent(payment_intent) do
      {:ok, charge} ->
        # Get the balance transaction to extract the fee
        case get_balance_transaction(charge.balance_transaction) do
          {:ok, balance_transaction} ->
            fee_cents = balance_transaction.fee || 0
            Money.new(:USD, Ysc.MoneyHelper.cents_to_dollars(fee_cents))

          {:error, _} ->
            # Fallback to estimated fee calculation
            amount_cents = payment_intent.amount
            estimated_fee_cents = trunc(amount_cents * 0.029 + 30)
            Money.new(:USD, Ysc.MoneyHelper.cents_to_dollars(estimated_fee_cents))
        end

      {:error, _} ->
        # Fallback to estimated fee calculation
        amount_cents = payment_intent.amount
        estimated_fee_cents = trunc(amount_cents * 0.029 + 30)
        Money.new(:USD, Ysc.MoneyHelper.cents_to_dollars(estimated_fee_cents))
    end
  end

  @doc false
  defp get_charge_from_payment_intent(payment_intent) do
    case payment_intent.charges do
      %Stripe.List{data: [charge | _]} ->
        {:ok, charge}

      _ ->
        {:error, :no_charge_found}
    end
  end

  @doc false
  defp get_balance_transaction(balance_transaction_id) do
    case Stripe.BalanceTransaction.retrieve(balance_transaction_id) do
      {:ok, balance_transaction} ->
        {:ok, balance_transaction}

      {:error, %Stripe.Error{} = error} ->
        {:error, error.message}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  defp confirm_tickets(tickets) do
    # Only update tickets that are not already confirmed (idempotency)
    tickets
    |> Enum.filter(fn ticket -> ticket.status != :confirmed end)
    |> Enum.each(fn ticket ->
      ticket
      |> Ysc.Events.Ticket.changeset(%{status: :confirmed})
      |> Ysc.Repo.update()
    end)

    :ok
  end

  defp create_stripe_customer(user) do
    customer_params = %{
      email: user.email,
      name: "#{user.first_name} #{user.last_name}",
      metadata: %{
        user_id: user.id
      }
    }

    case Stripe.Customer.create(customer_params) do
      {:ok, customer} ->
        # In a real implementation, you'd store the customer ID in the user record
        # For now, we'll just return it
        {:ok, customer.id}

      {:error, %Stripe.Error{} = error} ->
        {:error, error.message}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Helper function to safely convert Money to cents
  defp money_to_cents(%Money{amount: amount, currency: :USD}) do
    # Use Decimal for precise conversion to avoid floating-point errors
    amount
    |> Decimal.mult(100)
    |> Decimal.to_integer()
  end

  defp money_to_cents(%Money{amount: amount, currency: _currency}) do
    # For other currencies, use same conversion
    amount
    |> Decimal.mult(100)
    |> Decimal.to_integer()
  end

  defp money_to_cents(_) do
    # Fallback for invalid money values
    0
  end
end
