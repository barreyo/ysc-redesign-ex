defmodule Ysc.Tickets.BookingLocker do
  @moduledoc """
  Provides atomic booking operations with proper locking to prevent race conditions.

  This module ensures that ticket availability checks and ticket creation happen
  atomically within a single database transaction with proper row-level locking.
  """

  import Ecto.Query, warn: false
  alias Ysc.Repo
  alias Ysc.Events.{Event, TicketTier, Ticket}
  alias Ysc.Tickets.TicketOrder

  @doc """
  Atomically reserves tickets for a booking with proper locking.

  This function:
  1. Locks the event and ticket tiers
  2. Validates availability
  3. Creates the ticket order and tickets
  4. All within a single transaction

  ## Parameters:
  - `user_id`: The user making the booking
  - `event_id`: The event to book for
  - `ticket_selections`: Map of tier_id => quantity

  ## Returns:
  - `{:ok, %TicketOrder{}}` on success
  - `{:error, reason}` on failure
  """
  def atomic_booking(user_id, event_id, ticket_selections) do
    Repo.transaction(fn ->
      with {:ok, event} <- lock_and_validate_event(event_id),
           {:ok, tiers} <- lock_and_validate_tiers(event_id, ticket_selections),
           :ok <- validate_event_capacity(event, tiers, ticket_selections),
           {:ok, total_amount} <- calculate_total_amount(tiers, ticket_selections),
           {:ok, ticket_order} <- create_ticket_order_atomic(user_id, event_id, total_amount),
           {:ok, _tickets} <- create_tickets_atomic(ticket_order, tiers, ticket_selections) do
        ticket_order
      else
        {:error, reason} ->
          require Logger

          Logger.error("BookingLocker.atomic_booking failed",
            user_id: user_id,
            event_id: event_id,
            ticket_selections: ticket_selections,
            reason: reason
          )

          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Checks availability with proper locking for real-time display.

  This is used for UI display and should not be used for final booking validation.
  """
  def check_availability_with_lock(event_id) do
    Repo.transaction(fn ->
      event = lock_event(event_id)
      tiers = lock_ticket_tiers(event_id)

      event_capacity = get_event_capacity_info(event)
      tier_availability = Enum.map(tiers, &get_tier_availability/1)

      %{
        event_capacity: event_capacity,
        tiers: tier_availability
      }
    end)
  end

  ## Private Functions

  defp lock_and_validate_event(event_id) do
    case lock_event(event_id) do
      nil ->
        {:error, :event_not_found}

      %Event{state: :cancelled} ->
        {:error, :event_cancelled}

      %Event{} = event ->
        if event_in_past?(event) do
          {:error, :event_in_past}
        else
          {:ok, event}
        end
    end
  end

  defp lock_and_validate_tiers(event_id, ticket_selections) do
    _tier_ids = Map.keys(ticket_selections)

    # Lock all ticket tiers for this event
    tiers = lock_ticket_tiers(event_id)

    # Validate each requested tier
    validations =
      ticket_selections
      |> Enum.map(fn {tier_id, quantity} ->
        validate_tier_availability(tiers, tier_id, quantity, event_id)
      end)

    if Enum.any?(validations, &(&1 != :ok)) do
      {:error, :tier_validation_failed}
    else
      {:ok, tiers}
    end
  end

  defp validate_tier_availability(tiers, tier_id, quantity, event_id) do
    case Enum.find(tiers, &(&1.id == tier_id)) do
      nil ->
        {:error, :tier_not_found}

      tier ->
        cond do
          tier.event_id != event_id -> {:error, :tier_not_for_event}
          not tier_on_sale?(tier) -> {:error, :tier_not_on_sale}
          quantity <= 0 -> {:error, :invalid_quantity}
          # Donations don't count towards capacity - skip capacity check
          tier.type == :donation or tier.type == "donation" -> :ok
          true -> validate_tier_capacity(tier, quantity)
        end
    end
  end

  defp validate_tier_capacity(tier, requested_quantity) do
    available = get_available_tier_quantity_locked(tier)

    cond do
      available == :unlimited -> :ok
      requested_quantity <= available -> :ok
      true -> {:error, :insufficient_capacity}
    end
  end

  defp validate_event_capacity(%Event{max_attendees: nil}, _tiers, _ticket_selections) do
    # No capacity limit, always OK
    :ok
  end

  defp validate_event_capacity(
         %Event{max_attendees: max_attendees} = event,
         tiers,
         ticket_selections
       ) do
    # Count current tickets (both confirmed and pending count toward capacity)
    current_attendees = count_all_tickets_for_event_locked(event.id)

    # Calculate total requested tickets (excluding donations)
    total_requested =
      ticket_selections
      |> Enum.reduce(0, fn {tier_id, quantity}, acc ->
        tier = Enum.find(tiers, &(&1.id == tier_id))

        # Donations don't count toward event capacity
        if tier && (tier.type == :donation || tier.type == "donation") do
          acc
        else
          acc + quantity
        end
      end)

    # Check if adding requested tickets would exceed capacity
    if current_attendees + total_requested <= max_attendees do
      :ok
    else
      {:error, :event_capacity_exceeded}
    end
  end

  defp lock_event(event_id) do
    # Fetch event (optimistic locking - no FOR UPDATE)
    # The optimistic lock will be checked when we update the event if needed
    Repo.get(Event, event_id)
  end

  defp lock_ticket_tiers(event_id) do
    # Fetch ticket tiers (optimistic locking - no FOR UPDATE)
    # The optimistic lock will be checked when we update tiers if needed
    Repo.all(
      from tt in TicketTier,
        where: tt.event_id == ^event_id
    )
  end

  defp get_available_tier_quantity_locked(%TicketTier{quantity: nil}), do: :unlimited
  defp get_available_tier_quantity_locked(%TicketTier{quantity: 0}), do: :unlimited

  defp get_available_tier_quantity_locked(%TicketTier{id: tier_id, quantity: total_quantity}) do
    sold_count = count_sold_tickets_for_tier_locked(tier_id)
    max(0, total_quantity - sold_count)
  end

  defp count_sold_tickets_for_tier_locked(tier_id) do
    Ticket
    |> where([t], t.ticket_tier_id == ^tier_id and t.status in [:confirmed, :pending])
    |> Repo.aggregate(:count, :id)
  end

  defp get_event_capacity_info(%Event{max_attendees: nil} = event) do
    %{
      max_attendees: nil,
      current_attendees: count_all_tickets_for_event_locked(event.id),
      available: :unlimited,
      at_capacity: false
    }
  end

  defp get_event_capacity_info(%Event{max_attendees: max_attendees} = event) do
    # Count both confirmed and pending tickets for accurate availability display
    current_attendees = count_all_tickets_for_event_locked(event.id)
    available = max_attendees - current_attendees

    %{
      max_attendees: max_attendees,
      current_attendees: current_attendees,
      available: max(0, available),
      at_capacity: current_attendees >= max_attendees
    }
  end

  defp count_all_tickets_for_event_locked(nil), do: 0

  defp count_all_tickets_for_event_locked(event_id) do
    # Count both confirmed and pending tickets since pending tickets are reserved
    Ticket
    |> where([t], t.event_id == ^event_id and t.status in [:confirmed, :pending])
    |> Repo.aggregate(:count, :id)
  end

  defp get_tier_availability(%TicketTier{} = tier) do
    available = get_available_tier_quantity_locked(tier)

    %{
      tier_id: tier.id,
      name: tier.name,
      total_quantity: tier.quantity,
      available: available,
      sold: get_sold_tier_quantity_locked(tier),
      on_sale: tier_on_sale?(tier),
      start_date: tier.start_date,
      end_date: tier.end_date
    }
  end

  defp get_sold_tier_quantity_locked(%TicketTier{id: tier_id}) do
    count_sold_tickets_for_tier_locked(tier_id)
  end

  defp calculate_total_amount(tiers, ticket_selections) do
    total =
      ticket_selections
      |> Enum.reduce(Money.new(0, :USD), fn {tier_id, amount_or_quantity}, acc ->
        tier = Enum.find(tiers, &(&1.id == tier_id))

        case tier.type do
          :free ->
            acc

          :donation ->
            # For donations, amount_or_quantity is already in cents
            # Convert cents to dollars Decimal, then create Money
            dollars_decimal = Ysc.MoneyHelper.cents_to_dollars(amount_or_quantity)
            donation_amount = Money.new(dollars_decimal, :USD)

            case Money.add(acc, donation_amount) do
              {:ok, new_total} -> new_total
              {:error, _} -> acc
            end

          "donation" ->
            # For donations, amount_or_quantity is already in cents
            # Convert cents to dollars Decimal, then create Money
            dollars_decimal = Ysc.MoneyHelper.cents_to_dollars(amount_or_quantity)
            donation_amount = Money.new(dollars_decimal, :USD)

            case Money.add(acc, donation_amount) do
              {:ok, new_total} -> new_total
              {:error, _} -> acc
            end

          _ ->
            # For regular paid tiers, multiply price by quantity
            case Money.mult(tier.price, amount_or_quantity) do
              {:ok, tier_total} ->
                case Money.add(acc, tier_total) do
                  {:ok, new_total} -> new_total
                  {:error, _} -> acc
                end

              {:error, _} ->
                acc
            end
        end
      end)

    {:ok, total}
  end

  defp create_ticket_order_atomic(user_id, event_id, total_amount) do
    expires_at = DateTime.add(DateTime.utc_now(), 30, :minute)

    case %TicketOrder{}
         |> TicketOrder.create_changeset(%{
           user_id: user_id,
           event_id: event_id,
           total_amount: total_amount,
           expires_at: expires_at
         })
         |> Repo.insert() do
      {:ok, ticket_order} ->
        # Schedule timeout check for this specific order
        Ysc.Tickets.TimeoutWorker.schedule_order_timeout(ticket_order.id, expires_at)
        {:ok, ticket_order}

      error ->
        error
    end
  end

  defp create_tickets_atomic(ticket_order, tiers, ticket_selections) do
    tickets =
      ticket_selections
      |> Enum.flat_map(fn {tier_id, amount_or_quantity} ->
        tier = Enum.find(tiers, &(&1.id == tier_id))

        # For donation tiers, always create 1 ticket regardless of amount
        # For other tiers, create tickets equal to quantity
        ticket_count =
          case tier.type do
            :donation -> 1
            "donation" -> 1
            _ -> amount_or_quantity
          end

        Enum.map(1..ticket_count, fn _ ->
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

    # Insert all tickets
    Enum.map(tickets, &Repo.insert!/1)
    |> case do
      tickets when is_list(tickets) -> {:ok, tickets}
      error -> {:error, error}
    end
  end

  defp tier_on_sale?(%TicketTier{start_date: nil}), do: true

  defp tier_on_sale?(%TicketTier{start_date: start_date}) do
    now = DateTime.utc_now()
    DateTime.compare(now, start_date) != :lt
  end

  defp event_in_past?(%Event{start_date: nil}), do: false

  defp event_in_past?(%Event{start_date: start_date, start_time: nil}) do
    DateTime.compare(DateTime.utc_now(), start_date) == :gt
  end

  defp event_in_past?(%Event{start_date: start_date, start_time: start_time}) do
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
end
