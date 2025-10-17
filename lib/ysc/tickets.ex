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
    |> preload([:user, :event, :payment, tickets: :ticket_tier])
    |> Repo.one()
  end

  @doc """
  Gets a ticket order by reference ID.
  """
  def get_ticket_order_by_reference(reference_id) do
    TicketOrder
    |> where([to], to.reference_id == ^reference_id)
    |> preload([:user, :event, :payment, tickets: :ticket_tier])
    |> Repo.one()
  end

  @doc """
  Gets all ticket orders for a user.
  """
  def list_user_ticket_orders(user_id) do
    TicketOrder
    |> where([to], to.user_id == ^user_id)
    |> order_by([to], desc: to.inserted_at)
    |> preload([:tickets, :event])
    |> Repo.all()
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
    event = Events.get_event!(event_id)

    # Check if event is at capacity
    if is_event_at_capacity?(event) do
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
  def is_event_at_capacity?(%Event{max_attendees: nil}), do: false

  def is_event_at_capacity?(%Event{max_attendees: max_attendees} = event) do
    current_attendees = count_confirmed_tickets_for_event(event.id)
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
    with {:ok, payment_intent} <- Stripe.PaymentIntent.retrieve(payment_intent_id),
         :ok <- validate_payment_intent(payment_intent, ticket_order),
         {:ok, {payment, _transaction, _entries}} <-
           process_ledger_payment(ticket_order, payment_intent),
         {:ok, completed_order} <- complete_ticket_order(ticket_order, payment.id),
         :ok <- confirm_tickets(completed_order) do
      {:ok, completed_order}
    end
  end

  @doc """
  Processes a free ticket order (no payment required).
  """
  def process_free_ticket_order(ticket_order) do
    with {:ok, completed_order} <- complete_ticket_order(ticket_order, nil),
         :ok <- confirm_tickets(completed_order) do
      {:ok, completed_order}
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

  defp validate_event_availability(event_id) do
    case Events.get_event(event_id) do
      nil ->
        {:error, :event_not_found}

      %Event{state: :cancelled} ->
        {:error, :event_cancelled}

      %Event{} = event ->
        if is_event_in_past?(event) do
          {:error, :event_in_past}
        else
          {:ok, event}
        end
    end
  end

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
    user.subscriptions
    |> Enum.any?(&Ysc.Subscriptions.valid?/1)
  end

  defp validate_tier_capacity(tier_id, requested_quantity, event) do
    case Events.get_ticket_tier(tier_id) do
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

  defp calculate_total_amount(event_id, ticket_selections) do
    total =
      ticket_selections
      |> Enum.reduce(Money.new(0, :USD), fn {tier_id, quantity}, acc ->
        case Events.get_ticket_tier(tier_id) do
          %TicketTier{type: :free} ->
            acc

          %TicketTier{price: price} ->
            case Money.mult(price, quantity) do
              {:ok, tier_total} ->
                case Money.add(acc, tier_total) do
                  {:ok, new_total} -> new_total
                  {:error, _} -> acc
                end

              {:error, _} ->
                acc
            end

          nil ->
            acc
        end
      end)

    {:ok, total}
  end

  defp create_order_record(user_id, event_id, total_amount) do
    expires_at = get_order_expiration_time()

    %TicketOrder{}
    |> TicketOrder.create_changeset(%{
      user_id: user_id,
      event_id: event_id,
      total_amount: total_amount,
      expires_at: expires_at
    })
    |> Repo.insert()
  end

  defp create_tickets_for_order(ticket_order, ticket_selections) do
    tickets =
      ticket_selections
      |> Enum.flat_map(fn {tier_id, quantity} ->
        Enum.map(1..quantity, fn _ ->
          %Ticket{}
          |> Ticket.changeset(%{
            event_id: ticket_order.event_id,
            ticket_tier_id: tier_id,
            user_id: ticket_order.user_id,
            ticket_order_id: ticket_order.id,
            status: :pending,
            expires_at: ticket_order.expires_at
          })
        end)
      end)

    # Insert all tickets in a single transaction
    Repo.transaction(fn ->
      Enum.map(tickets, &Repo.insert!/1)
    end)
  end

  defp validate_payment_intent(payment_intent, ticket_order) do
    expected_amount = Money.to_cents(ticket_order.total_amount)

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
      payment_method_id: extract_payment_method_id(payment_intent)
    })
  end

  defp extract_stripe_fee(payment_intent) do
    # Stripe fee is typically calculated as 2.9% + 30¢
    # This is a simplified calculation - in production you'd get this from the charge object
    amount_cents = payment_intent.amount
    fee_cents = trunc(amount_cents * 0.029 + 30)
    Money.new(fee_cents, :USD)
  end

  defp extract_payment_method_id(payment_intent) do
    # Extract payment method ID from payment intent
    # This would need to be implemented based on your Stripe setup
    nil
  end

  defp confirm_tickets(ticket_order) do
    # Query for tickets directly to avoid association loading issues
    tickets = Repo.all(from t in Ticket, where: t.ticket_order_id == ^ticket_order.id)

    tickets
    |> Enum.each(fn ticket ->
      ticket
      |> Ticket.changeset(%{status: :confirmed})
      |> Repo.update()
    end)

    :ok
  end

  defp is_event_in_past?(%Event{start_date: nil}), do: false

  defp is_event_in_past?(%Event{start_date: start_date, start_time: nil}) do
    DateTime.compare(DateTime.utc_now(), start_date) == :gt
  end

  defp is_event_in_past?(%Event{start_date: start_date, start_time: start_time}) do
    event_datetime = combine_date_time(start_date, start_time)
    DateTime.compare(DateTime.utc_now(), event_datetime) == :gt
  end

  defp combine_date_time(date, time) do
    case {date, time} do
      {%DateTime{} = dt, %Time{} = t} ->
        naive_date = DateTime.to_naive(dt)
        date_part = NaiveDateTime.to_date(naive_date)
        naive_datetime = NaiveDateTime.new!(date_part, t)
        DateTime.from_naive!(naive_datetime, "Etc/UTC")

      {date, time} when not is_nil(date) and not is_nil(time) ->
        NaiveDateTime.new!(date, time)
        |> DateTime.from_naive!("Etc/UTC")
    end
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

  defp broadcast(event) do
    Phoenix.PubSub.broadcast(Ysc.PubSub, topic(), {__MODULE__, event})
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
end
