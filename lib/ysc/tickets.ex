defmodule Ysc.Tickets do
  @moduledoc """
  The Tickets context for managing ticket orders and individual tickets.

  This module provides utilities for:
  - Creating ticket orders with multiple tickets
  - Validating booking capacity and preventing overbooking
  - Processing payments with Stripe integration
  - Managing 15-minute payment timeouts
  - Handling ticket order lifecycle
  """

  import Ecto.Query, warn: false
  alias Ysc.Repo

  alias Ysc.Tickets.TicketOrder
  alias Ysc.Tickets.BookingLocker
  alias Ysc.Events.Ticket
  alias Ysc.Events.TicketTier
  alias Ysc.Events.Event
  alias Ysc.Accounts
  alias Ysc.Ledgers

  @payment_timeout_minutes 15

  ## Ticket Order Management

  @doc """
  Creates a new ticket order with multiple tickets.

  This function:
  - Validates user membership
  - Cancels older pending orders for the user (keeps newest session)
  - Uses atomic booking to prevent overbooking
  - Creates tickets with pending status
  - Schedules timeout cleanup

  ## Parameters:
  - `user_id`: The user purchasing tickets
  - `event_id`: The event being purchased for
  - `ticket_selections`: Map of ticket_tier_id => quantity

  ## Returns:
  - `{:ok, %TicketOrder{}}` on success
  - `{:error, changeset}` on validation failure
  - `{:error, :overbooked}` if event or tier capacity exceeded
  - `{:error, :event_not_available}` if event is not available for purchase
  - `{:error, :membership_required}` if user doesn't have active membership
  """
  def create_ticket_order(user_id, event_id, ticket_selections) do
    require Logger

    Logger.info("Creating ticket order",
      user_id: user_id,
      event_id: event_id,
      ticket_selections: ticket_selections
    )

    with {:ok, _} <- validate_user_membership(user_id),
         {:ok, ticket_order} <- BookingLocker.atomic_booking(user_id, event_id, ticket_selections) do
      {:ok, ticket_order}
    else
      error ->
        require Logger

        Logger.error("Failed to create ticket order",
          user_id: user_id,
          event_id: event_id,
          ticket_selections: ticket_selections,
          error: error
        )

        error
    end
  end

  @doc """
  Gets a ticket order by ID with preloaded tickets.
  """
  def get_ticket_order(id) do
    TicketOrder
    |> where([to], to.id == ^id)
    |> preload([
      :user,
      event: [agendas: :agenda_items],
      payment: :payment_method,
      tickets: :ticket_tier
    ])
    |> Repo.one()
  end

  @doc """
  Gets a ticket order by reference ID.
  """
  def get_ticket_order_by_reference(reference_id) do
    TicketOrder
    |> where([to], to.reference_id == ^reference_id)
    |> preload([
      :user,
      :event,
      payment: :payment_method,
      tickets: :ticket_tier
    ])
    |> Repo.one()
  end

  @doc """
  Gets all ticket orders for a user.
  """
  def list_user_ticket_orders(user_id) do
    TicketOrder
    |> where([to], to.user_id == ^user_id)
    |> order_by([to], desc: to.inserted_at)
    |> preload([:tickets, :event, tickets: :ticket_tier])
    |> Repo.all()
  end

  @doc """
  Gets paginated ticket orders for a user with Flop.
  """
  def list_user_ticket_orders_paginated(user_id, params) do
    base_query =
      from(to in TicketOrder,
        where: to.user_id == ^user_id,
        preload: [:tickets, :event, :payment, tickets: :ticket_tier]
      )

    case Flop.validate_and_run(base_query, params, for: TicketOrder) do
      {:ok, {orders, meta}} ->
        {:ok, {orders, meta}}

      error ->
        error
    end
  end

  @doc """
  Gets all confirmed tickets for a user for a specific event.
  """
  def list_user_tickets_for_event(user_id, event_id) do
    Ticket
    |> where([t], t.user_id == ^user_id and t.event_id == ^event_id and t.status == :confirmed)
    |> order_by([t], desc: t.inserted_at)
    |> preload([:ticket_tier, :ticket_order])
    |> Repo.all()
  end

  @doc """
  Updates a ticket order's payment intent ID.
  """
  def update_payment_intent(ticket_order, payment_intent_id) do
    ticket_order
    |> TicketOrder.payment_changeset(%{payment_intent_id: payment_intent_id})
    |> Repo.update()
  end

  @doc """
  Marks a ticket order as completed after successful payment.
  """
  def complete_ticket_order(ticket_order, payment_id) do
    ticket_order
    |> TicketOrder.status_changeset(%{
      status: :completed,
      payment_id: payment_id,
      completed_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @doc """
  Cancels a ticket order and releases the reserved tickets.
  """
  def cancel_ticket_order(ticket_order, reason \\ "User cancelled") do
    result =
      Repo.transaction(fn ->
        # Update ticket order status
        {:ok, updated_order} =
          ticket_order
          |> TicketOrder.status_changeset(%{
            status: :cancelled,
            cancelled_at: DateTime.utc_now(),
            cancellation_reason: reason
          })
          |> Repo.update()

        # Cancel all associated tickets
        tickets = Repo.all(from t in Ticket, where: t.ticket_order_id == ^ticket_order.id)

        Enum.each(tickets, fn ticket ->
          ticket
          |> Ticket.changeset(%{status: :cancelled})
          |> Repo.update()
        end)

        updated_order
      end)

    # Broadcast the cancellation event
    case result do
      {:ok, updated_order} ->
        event = %Ysc.MessagePassingEvents.CheckoutSessionCancelled{
          ticket_order: updated_order,
          user_id: updated_order.user_id,
          event_id: updated_order.event_id,
          reason: reason
        }

        require Logger

        Logger.info("Broadcasting CheckoutSessionCancelled event",
          user_id: updated_order.user_id,
          event_id: updated_order.event_id,
          reason: reason
        )

        broadcast_to_user(updated_order.user_id, event)
        result

      error ->
        error
    end
  end

  @doc """
  Expires a ticket order that has exceeded the payment timeout.
  """
  def expire_ticket_order(ticket_order) do
    result =
      Repo.transaction(fn ->
        # Update ticket order status
        {:ok, updated_order} =
          ticket_order
          |> TicketOrder.status_changeset(%{
            status: :expired,
            cancelled_at: DateTime.utc_now(),
            cancellation_reason: "Payment timeout"
          })
          |> Repo.update()

        # Cancel all associated tickets
        tickets = Repo.all(from t in Ticket, where: t.ticket_order_id == ^ticket_order.id)

        Enum.each(tickets, fn ticket ->
          ticket
          |> Ticket.changeset(%{status: :expired})
          |> Repo.update()
        end)

        updated_order
      end)

    # Broadcast the expiration event
    case result do
      {:ok, updated_order} ->
        event = %Ysc.MessagePassingEvents.CheckoutSessionExpired{
          ticket_order: updated_order,
          user_id: updated_order.user_id,
          event_id: updated_order.event_id
        }

        broadcast_to_user(updated_order.user_id, event)
        result

      error ->
        error
    end
  end

  ## Booking Validation

  @doc """
  Validates that the requested ticket quantities don't exceed available capacity.
  """
  def validate_booking_capacity(event_id, ticket_selections) do
    event = Ysc.Events.get_event!(event_id)

    # Check if event is at capacity
    if event_at_capacity?(event) do
      {:error, :event_at_capacity}
    else
      # Check each ticket tier capacity
      tier_validations =
        ticket_selections
        |> Enum.map(fn {tier_id, quantity} ->
          validate_tier_capacity(tier_id, quantity, event)
        end)

      if Enum.any?(tier_validations, &(&1 == :error)) do
        {:error, :tier_capacity_exceeded}
      else
        # Check total event capacity
        total_requested = Enum.sum(Map.values(ticket_selections))

        if within_event_capacity?(event, total_requested) do
          :ok
        else
          {:error, :event_capacity_exceeded}
        end
      end
    end
  end

  @doc """
  Checks if an event is at its maximum capacity.
  """
  def event_at_capacity?(%Event{max_attendees: nil}), do: false

  def event_at_capacity?(%Event{max_attendees: max_attendees} = event) do
    current_attendees = count_confirmed_tickets_for_event(event.id)
    current_attendees >= max_attendees
  end

  # Handle maps (from our custom query)
  def event_at_capacity?(%{max_attendees: nil}), do: false

  def event_at_capacity?(%{max_attendees: max_attendees, id: event_id}) do
    current_attendees = count_confirmed_tickets_for_event(event_id)
    current_attendees >= max_attendees
  end

  @doc """
  Counts the total number of confirmed tickets for an event.
  """
  def count_confirmed_tickets_for_event(event_id) do
    Ticket
    |> where([t], t.event_id == ^event_id and t.status == :confirmed)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Counts the total number of pending tickets for an event (including expired ones that haven't been cleaned up).
  """
  def count_pending_tickets_for_event(event_id) do
    Ticket
    |> where([t], t.event_id == ^event_id and t.status == :pending)
    |> Repo.aggregate(:count, :id)
  end

  ## Payment Processing

  @doc """
  Processes payment for a ticket order using Stripe.
  """
  def process_ticket_order_payment(ticket_order, payment_intent_id) do
    with {:ok, payment_intent} <- Stripe.PaymentIntent.retrieve(payment_intent_id, %{}),
         :ok <- validate_payment_intent(payment_intent, ticket_order),
         {:ok, {payment, _transaction, _entries}} <-
           process_ledger_payment(ticket_order, payment_intent),
         {:ok, completed_order} <- complete_ticket_order(ticket_order, payment.id),
         :ok <- confirm_tickets(completed_order) do
      # Reload the completed order with all necessary associations for email
      reloaded_order = get_ticket_order(completed_order.id)
      # Send confirmation email
      send_ticket_confirmation_email(reloaded_order)
      {:ok, reloaded_order}
    end
  end

  @doc """
  Processes a free ticket order (no payment required).
  """
  def process_free_ticket_order(ticket_order) do
    with {:ok, completed_order} <- complete_ticket_order(ticket_order, nil),
         :ok <- confirm_tickets(completed_order) do
      # Reload the completed order with all necessary associations for email
      reloaded_order = get_ticket_order(completed_order.id)
      # Send confirmation email
      send_ticket_confirmation_email(reloaded_order)
      {:ok, reloaded_order}
    end
  end

  ## Timeout Management

  @doc """
  Finds and expires ticket orders that have exceeded the payment timeout.
  """
  def expire_timed_out_orders do
    timeout_threshold = DateTime.add(DateTime.utc_now(), -@payment_timeout_minutes, :minute)

    TicketOrder
    |> where([to], to.status == :pending and to.expires_at < ^timeout_threshold)
    |> preload(:tickets)
    |> Repo.all()
    |> Enum.each(&expire_ticket_order/1)
  end

  @doc """
  Utility function to expire all current pending checkout sessions.

  This is useful for:
  - Admin operations
  - Testing scenarios
  - Maintenance tasks
  - Emergency situations

  ## Returns:
  - `{:ok, count}` where count is the number of expired sessions
  - `{:error, reason}` if there was an error
  """
  def expire_all_pending_checkout_sessions do
    require Logger

    try do
      pending_orders =
        TicketOrder
        |> where([to], to.status == :pending)
        |> preload(:tickets)
        |> Repo.all()

      count = length(pending_orders)

      if count > 0 do
        Logger.info("Manually expiring all pending checkout sessions",
          total_sessions: count
        )

        Enum.each(pending_orders, fn ticket_order ->
          expire_ticket_order(ticket_order)
        end)

        Logger.info("Successfully expired all pending checkout sessions",
          expired_count: count
        )
      else
        Logger.info("No pending checkout sessions found to expire")
      end

      {:ok, count}
    rescue
      error ->
        require Logger

        Logger.error("Failed to expire pending checkout sessions",
          error: error
        )

        {:error, error}
    end
  end

  @doc """
  Utility function to expire pending checkout sessions for a specific user.

  ## Parameters:
  - `user_id`: The user ID to expire sessions for

  ## Returns:
  - `{:ok, count}` where count is the number of expired sessions
  - `{:error, reason}` if there was an error
  """
  def expire_user_pending_checkout_sessions(user_id) do
    require Logger

    try do
      pending_orders =
        TicketOrder
        |> where([to], to.user_id == ^user_id and to.status == :pending)
        |> preload(:tickets)
        |> Repo.all()

      count = length(pending_orders)

      if count > 0 do
        Logger.info("Manually expiring pending checkout sessions for user",
          user_id: user_id,
          total_sessions: count
        )

        Enum.each(pending_orders, fn ticket_order ->
          expire_ticket_order(ticket_order)
        end)

        Logger.info("Successfully expired user's pending checkout sessions",
          user_id: user_id,
          expired_count: count
        )
      else
        Logger.info("No pending checkout sessions found for user",
          user_id: user_id
        )
      end

      {:ok, count}
    rescue
      error ->
        require Logger

        Logger.error("Failed to expire user's pending checkout sessions",
          user_id: user_id,
          error: error
        )

        {:error, error}
    end
  end

  @doc """
  Utility function to expire pending checkout sessions for a specific event.

  ## Parameters:
  - `event_id`: The event ID to expire sessions for

  ## Returns:
  - `{:ok, count}` where count is the number of expired sessions
  - `{:error, reason}` if there was an error
  """
  def expire_event_pending_checkout_sessions(event_id) do
    require Logger

    try do
      pending_orders =
        TicketOrder
        |> where([to], to.event_id == ^event_id and to.status == :pending)
        |> preload(:tickets)
        |> Repo.all()

      count = length(pending_orders)

      if count > 0 do
        Logger.info("Manually expiring pending checkout sessions for event",
          event_id: event_id,
          total_sessions: count
        )

        Enum.each(pending_orders, fn ticket_order ->
          expire_ticket_order(ticket_order)
        end)

        Logger.info("Successfully expired event's pending checkout sessions",
          event_id: event_id,
          expired_count: count
        )
      else
        Logger.info("No pending checkout sessions found for event",
          event_id: event_id
        )
      end

      {:ok, count}
    rescue
      error ->
        require Logger

        Logger.error("Failed to expire event's pending checkout sessions",
          event_id: event_id,
          error: error
        )

        {:error, error}
    end
  end

  @doc """
  Gets the expiration time for a new ticket order.
  """
  def get_order_expiration_time do
    DateTime.add(DateTime.utc_now(), @payment_timeout_minutes, :minute)
  end

  @doc """
  Gets statistics about pending checkout sessions.

  ## Returns:
  - Map with statistics about pending sessions
  """
  def get_pending_checkout_statistics do
    pending_orders =
      TicketOrder
      |> where([to], to.status == :pending)
      |> preload([:tickets, :user, :event])
      |> Repo.all()

    total_sessions = length(pending_orders)

    total_tickets =
      Enum.reduce(pending_orders, 0, fn order, acc -> acc + length(order.tickets) end)

    # Group by event
    event_stats =
      pending_orders
      |> Enum.group_by(& &1.event_id)
      |> Enum.map(fn {event_id, orders} ->
        event = hd(orders).event

        %{
          event_id: event_id,
          event_title: event.title,
          pending_sessions: length(orders),
          pending_tickets:
            Enum.reduce(orders, 0, fn order, acc -> acc + length(order.tickets) end)
        }
      end)

    # Group by user
    user_stats =
      pending_orders
      |> Enum.group_by(& &1.user_id)
      |> Enum.map(fn {user_id, orders} ->
        user = hd(orders).user

        %{
          user_id: user_id,
          user_email: user.email,
          pending_sessions: length(orders),
          pending_tickets:
            Enum.reduce(orders, 0, fn order, acc -> acc + length(order.tickets) end)
        }
      end)

    %{
      total_pending_sessions: total_sessions,
      total_pending_tickets: total_tickets,
      by_event: event_stats,
      by_user: user_stats,
      generated_at: DateTime.utc_now()
    }
  end

  ## Private Functions

  defp validate_user_membership(user_id) do
    case Accounts.get_user!(user_id, [:subscriptions]) do
      nil ->
        {:error, :user_not_found}

      user ->
        if has_active_membership?(user) do
          {:ok, user}
        else
          {:error, :membership_required}
        end
    end
  end

  defp has_active_membership?(user) do
    Accounts.has_active_membership?(user)
  end

  defp validate_tier_capacity(tier_id, requested_quantity, _event) do
    case Ysc.Events.get_ticket_tier(tier_id) do
      nil ->
        :error

      tier ->
        available = get_available_tier_quantity(tier)

        if available == :unlimited or requested_quantity <= available do
          :ok
        else
          :error
        end
    end
  end

  defp get_available_tier_quantity(%TicketTier{quantity: nil}), do: :unlimited
  defp get_available_tier_quantity(%TicketTier{quantity: 0}), do: :unlimited

  defp get_available_tier_quantity(%TicketTier{id: tier_id, quantity: total_quantity}) do
    sold_count = count_sold_tickets_for_tier(tier_id)
    max(0, total_quantity - sold_count)
  end

  defp count_sold_tickets_for_tier(tier_id) do
    Ticket
    |> where([t], t.ticket_tier_id == ^tier_id and t.status in [:confirmed, :pending])
    |> Repo.aggregate(:count, :id)
  end

  defp within_event_capacity?(%Event{max_attendees: nil}, _), do: true

  defp within_event_capacity?(%Event{max_attendees: max_attendees}, requested_quantity) do
    current_attendees = count_confirmed_tickets_for_event(max_attendees)
    current_attendees + requested_quantity <= max_attendees
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

  defp process_ledger_payment(ticket_order, payment_intent) do
    Ledgers.process_payment(%{
      user_id: ticket_order.user_id,
      amount: ticket_order.total_amount,
      entity_type: :event,
      entity_id: ticket_order.event_id,
      external_payment_id: payment_intent.id,
      stripe_fee: extract_stripe_fee(payment_intent),
      description: "Event tickets - Order #{ticket_order.reference_id}",
      property: nil,
      payment_method_id: extract_payment_method_id(payment_intent, ticket_order.user_id)
    })
  end

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

  defp get_charge_from_payment_intent(payment_intent) do
    case payment_intent.charges do
      %Stripe.List{data: [charge | _]} ->
        {:ok, charge}

      _ ->
        {:error, :no_charge_found}
    end
  end

  defp get_balance_transaction(balance_transaction_id) when is_binary(balance_transaction_id) do
    case Stripe.BalanceTransaction.retrieve(balance_transaction_id) do
      {:ok, balance_transaction} ->
        {:ok, balance_transaction}

      {:error, %Stripe.Error{} = error} ->
        {:error, error.message}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_balance_transaction(_), do: {:error, :invalid_balance_transaction_id}

  defp extract_payment_method_id(payment_intent, user_id) do
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

  defp confirm_tickets(ticket_order) do
    # Query for tickets directly to avoid association loading issues
    # Only update tickets that are not already confirmed (idempotency)
    tickets =
      Repo.all(
        from t in Ticket,
          where: t.ticket_order_id == ^ticket_order.id and t.status != :confirmed
      )

    tickets
    |> Enum.each(fn ticket ->
      ticket
      |> Ticket.changeset(%{status: :confirmed})
      |> Repo.update()
    end)

    :ok
  end

  ## PubSub Functions

  @doc """
  Subscribe to ticket-related events.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Ysc.PubSub, topic())
  end

  @doc """
  Subscribe to ticket events for a specific user.
  """
  def subscribe(user_id) do
    Phoenix.PubSub.subscribe(Ysc.PubSub, topic(user_id))
  end

  defp topic do
    "tickets"
  end

  defp topic(user_id) do
    "tickets:user:#{user_id}"
  end

  defp broadcast_to_user(user_id, event) do
    topic_name = topic(user_id)
    require Logger

    Logger.info("Broadcasting to user topic",
      user_id: user_id,
      topic: topic_name,
      event_type: event.__struct__,
      event_data: inspect(event, limit: :infinity)
    )

    result = Phoenix.PubSub.broadcast(Ysc.PubSub, topic_name, {__MODULE__, event})

    Logger.info("PubSub broadcast result",
      user_id: user_id,
      topic: topic_name,
      result: result
    )

    result
  end

  @doc """
  Test function to manually broadcast a CheckoutSessionCancelled event.
  This is useful for debugging PubSub connectivity.
  """
  def test_broadcast_checkout_cancelled(user_id) do
    require Logger

    Logger.info("TEST: Manually broadcasting CheckoutSessionCancelled event",
      user_id: user_id,
      topic: topic(user_id)
    )

    event = %Ysc.MessagePassingEvents.CheckoutSessionCancelled{
      ticket_order: nil,
      user_id: user_id,
      event_id: nil,
      reason: "Manual test broadcast"
    }

    broadcast_to_user(user_id, event)

    Logger.info("TEST: Broadcast completed")
    :ok
  end

  @doc """
  Sends a ticket purchase confirmation email for a completed ticket order.
  """
  def send_ticket_confirmation_email(ticket_order) do
    require Logger

    Logger.info("Starting ticket confirmation email process",
      ticket_order_id: ticket_order.id,
      user_id: ticket_order.user_id,
      user_email: ticket_order.user.email,
      completed_at: ticket_order.completed_at
    )

    try do
      # Prepare email data
      Logger.info("Preparing email data for ticket order #{ticket_order.id}")
      email_data = YscWeb.Emails.TicketPurchaseConfirmation.prepare_email_data(ticket_order)
      Logger.info("Email data prepared successfully", email_data_keys: Map.keys(email_data))

      # Generate idempotency key
      idempotency_key = "ticket_confirmation_#{ticket_order.id}"

      Logger.info("Generated idempotency key: #{idempotency_key}")

      # Schedule the email
      Logger.info("Scheduling email with Oban")

      result =
        YscWeb.Emails.Notifier.schedule_email(
          ticket_order.user.email,
          idempotency_key,
          YscWeb.Emails.TicketPurchaseConfirmation.get_subject(),
          "ticket_purchase_confirmation",
          email_data,
          "",
          ticket_order.user_id
        )

      case result do
        %Oban.Job{} = job ->
          Logger.info("Ticket confirmation email scheduled successfully",
            ticket_order_id: ticket_order.id,
            user_id: ticket_order.user_id,
            user_email: ticket_order.user.email,
            job_id: job.id,
            idempotency_key: idempotency_key
          )

          :ok

        {:error, reason} ->
          Logger.error("Failed to schedule email",
            ticket_order_id: ticket_order.id,
            user_id: ticket_order.user_id,
            error: reason
          )

          :error
      end
    rescue
      error ->
        Logger.error("Failed to send ticket confirmation email",
          ticket_order_id: ticket_order.id,
          user_id: ticket_order.user_id,
          user_email: ticket_order.user.email,
          error: error,
          stacktrace: __STACKTRACE__
        )

        :error
    end
  end
end
