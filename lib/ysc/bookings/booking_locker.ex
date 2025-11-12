defmodule Ysc.Bookings.BookingLocker do
  @moduledoc """
  Provides atomic booking operations with proper locking to prevent race conditions.

  This module ensures that inventory availability checks and booking creation happen
  atomically within a single database transaction with proper row-level locking.

  ## Booking Flows

  ### A) Buyout (Tahoe summer or Clear Lake, when allowed)
  - Locks property_inventory rows for all days
  - Ensures: buyout_* false AND (for Tahoe) no room_inventory held/booked
  - Marks buyout_held = true, creates booking in :hold
  - After payment → flip to buyout_booked = true and set booking :complete
  - On failure/expiry → reset buyout_held = false, set booking :expired|:canceled

  ### B) Tahoe per-room
  - Locks room_inventory for the target room across the range
  - Locks property_inventory to check buyout flags
  - Ensures room not held/booked and property no buyout
  - Sets held = true on room_inventory; creates booking :hold
  - Confirm → booked = true (clear held)
  - Release → clear held

  ### C) Clear Lake per-guest
  - Locks property_inventory for all days
  - Ensures buyout flags false and capacity_booked + capacity_held + guests <= capacity_total
  - Increments capacity_held; creates booking :hold
  - Confirm → decrement held, increment booked
  - Release → decrement held
  """

  import Ecto.Query, warn: false
  require Logger

  alias Ysc.Repo

  alias Ysc.Bookings.{
    Booking,
    PropertyInventory,
    RoomInventory,
    Season,
    Room
  }

  alias Ysc.Bookings

  @hold_duration_minutes 30

  # Default capacity per property (can be overridden by season policy)
  @default_capacity_clear_lake 12
  # Tahoe uses room-level inventory, not property capacity
  @default_capacity_tahoe 0

  @doc """
  Atomically creates a buyout booking with proper inventory locking.

  ## Parameters:
  - `user_id`: The user making the booking
  - `property`: The property (:tahoe or :clear_lake)
  - `checkin_date`: Check-in date
  - `checkout_date`: Check-out date
  - `guests_count`: Number of guests
  - `opts`: Additional options (e.g., `hold_duration_minutes`)

  ## Returns:
  - `{:ok, %Booking{}}` on success
  - `{:error, reason}` on failure
  """
  def create_buyout_booking(
        user_id,
        property,
        checkin_date,
        checkout_date,
        guests_count,
        opts \\ []
      ) do
    hold_duration = Keyword.get(opts, :hold_duration_minutes, @hold_duration_minutes)
    hold_expires_at = DateTime.add(DateTime.utc_now(), hold_duration, :minute)

    Repo.transaction(fn ->
      days = Date.range(checkin_date, Date.add(checkout_date, -1)) |> Enum.to_list()

      # Ensure property_inventory rows exist
      for day <- days do
        capacity_total = get_property_capacity_for_date(property, day)
        ensure_property_inventory_row(property, day, capacity_total)
      end

      # Lock property_inventory rows for all days
      locked_prop_inv =
        Repo.all(
          from pi in PropertyInventory,
            where:
              pi.property == ^property and pi.day >= ^checkin_date and pi.day < ^checkout_date,
            lock: "FOR UPDATE"
        )

      # If Tahoe has rooms, ensure no room activity blocks buyout
      if property == :tahoe do
        locked_room_inv =
          Repo.all(
            from ri in RoomInventory,
              join: r in Room,
              on: ri.room_id == r.id,
              where:
                r.property == ^property and ri.day >= ^checkin_date and ri.day < ^checkout_date,
              lock: "FOR UPDATE"
          )

        # Validate no held/booked rooms for any day
        blocked_days =
          Enum.filter(locked_room_inv, fn ri -> ri.held == true or ri.booked == true end)

        if length(blocked_days) > 0 do
          Repo.rollback({:error, :rooms_already_booked})
        end
      end

      # Validate no buyout held/booked and no per-guest counts (Clear Lake)
      invalid_days =
        Enum.filter(locked_prop_inv, fn pi ->
          pi.buyout_held == true or
            pi.buyout_booked == true or
            (property == :clear_lake and (pi.capacity_held > 0 or pi.capacity_booked > 0))
        end)

      if length(invalid_days) > 0 do
        Repo.rollback({:error, :property_unavailable})
      end

      # Set buyout_held = true for the range
      {count, _} =
        Repo.update_all(
          from(pi in PropertyInventory,
            where:
              pi.property == ^property and pi.day >= ^checkin_date and pi.day < ^checkout_date
          ),
          set: [buyout_held: true, updated_at: DateTime.truncate(DateTime.utc_now(), :second)]
        )

      if count == 0 do
        Repo.rollback({:error, :inventory_update_failed})
      end

      # Calculate pricing
      {total_price, pricing_items} =
        case Bookings.calculate_booking_price(
               property,
               checkin_date,
               checkout_date,
               :buyout,
               nil,
               guests_count,
               0
             ) do
          {:ok, total} ->
            nights = Date.diff(checkout_date, checkin_date)
            price_per_night = if nights > 0, do: Money.div(total, nights) |> elem(1), else: total

            items = %{
              "type" => "buyout",
              "nights" => nights,
              "price_per_night" => %{
                "amount" => Decimal.to_string(price_per_night.amount),
                "currency" => Atom.to_string(price_per_night.currency)
              },
              "total" => %{
                "amount" => Decimal.to_string(total.amount),
                "currency" => Atom.to_string(total.currency)
              }
            }

            {total, items}

          {:error, _reason} ->
            {nil, nil}
        end

      # Create booking in :hold
      attrs = %{
        property: property,
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        booking_mode: :buyout,
        guests_count: guests_count,
        user_id: user_id,
        status: :hold,
        hold_expires_at: hold_expires_at,
        total_price: total_price,
        pricing_items: pricing_items
      }

      case %Booking{}
           |> Booking.changeset(attrs, skip_validation: true)
           |> Repo.insert() do
        {:ok, booking} ->
          booking

        {:error, changeset} ->
          Repo.rollback({:error, changeset})
      end
    end)
  end

  @doc """
  Atomically creates a per-room booking with proper inventory locking.

  ## Parameters:
  - `user_id`: The user making the booking
  - `room_id`: The room to book
  - `checkin_date`: Check-in date
  - `checkout_date`: Check-out date
  - `guests_count`: Number of guests
  - `opts`: Additional options (e.g., `hold_duration_minutes`)

  ## Returns:
  - `{:ok, %Booking{}}` on success
  - `{:error, reason}` on failure
  """
  def create_room_booking(user_id, room_id, checkin_date, checkout_date, guests_count, opts \\ []) do
    children_count = Keyword.get(opts, :children_count, 0)
    hold_duration = Keyword.get(opts, :hold_duration_minutes, @hold_duration_minutes)
    hold_expires_at = DateTime.add(DateTime.utc_now(), hold_duration, :minute)

    Repo.transaction(fn ->
      days = Date.range(checkin_date, Date.add(checkout_date, -1)) |> Enum.to_list()

      # Get room to determine property
      room = Repo.get!(Room, room_id)
      property = room.property

      # Ensure property_inventory rows exist (for buyout check)
      for day <- days do
        capacity_total = get_property_capacity_for_date(property, day)
        ensure_property_inventory_row(property, day, capacity_total)
      end

      # Ensure room_inventory rows exist
      for day <- days do
        ensure_room_inventory_row(room_id, day)
      end

      # Lock room_inventory and property_inventory rows FOR UPDATE
      locked_room_inv =
        Repo.all(
          from ri in RoomInventory,
            where: ri.room_id == ^room_id and ri.day >= ^checkin_date and ri.day < ^checkout_date,
            lock: "FOR UPDATE"
        )

      locked_prop_inv =
        Repo.all(
          from pi in PropertyInventory,
            where:
              pi.property == ^property and pi.day >= ^checkin_date and pi.day < ^checkout_date,
            lock: "FOR UPDATE"
        )

      # Validate (no buyout; room free)
      # Check buyout flags
      buyout_blocked =
        Enum.any?(locked_prop_inv, fn pi -> pi.buyout_held == true or pi.buyout_booked == true end)

      if buyout_blocked do
        Repo.rollback({:error, :property_buyout_active})
      end

      # Check room availability
      room_blocked =
        Enum.any?(locked_room_inv, fn ri -> ri.held == true or ri.booked == true end)

      if room_blocked do
        Repo.rollback({:error, :room_unavailable})
      end

      # Set held = true on room_inventory
      {count, _} =
        Repo.update_all(
          from(ri in RoomInventory,
            where: ri.room_id == ^room_id and ri.day >= ^checkin_date and ri.day < ^checkout_date
          ),
          set: [held: true, updated_at: DateTime.truncate(DateTime.utc_now(), :second)]
        )

      if count == 0 do
        Repo.rollback({:error, :inventory_update_failed})
      end

      # Calculate pricing
      {total_price, pricing_items} =
        case Bookings.calculate_booking_price(
               property,
               checkin_date,
               checkout_date,
               :room,
               room_id,
               guests_count,
               children_count
             ) do
          {:ok, total} ->
            nights = Date.diff(checkout_date, checkin_date)
            items = build_room_pricing_items(room, total, nights, guests_count, children_count)
            {total, items}

          {:error, _reason} ->
            {nil, nil}
        end

      # Create booking :hold
      attrs = %{
        property: property,
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        booking_mode: :room,
        room_id: room_id,
        guests_count: guests_count,
        children_count: children_count,
        user_id: user_id,
        status: :hold,
        hold_expires_at: hold_expires_at,
        total_price: total_price,
        pricing_items: pricing_items
      }

      case %Booking{}
           |> Booking.changeset(attrs, skip_validation: true)
           |> Repo.insert() do
        {:ok, booking} ->
          booking

        {:error, changeset} ->
          Repo.rollback({:error, changeset})
      end
    end)
  end

  @doc """
  Atomically creates a per-guest booking (Clear Lake) with proper inventory locking.

  ## Parameters:
  - `user_id`: The user making the booking
  - `property`: The property (should be :clear_lake)
  - `checkin_date`: Check-in date
  - `checkout_date`: Check-out date
  - `guests_count`: Number of guests
  - `opts`: Additional options (e.g., `hold_duration_minutes`)

  ## Returns:
  - `{:ok, %Booking{}}` on success
  - `{:error, reason}` on failure
  """
  def create_per_guest_booking(
        user_id,
        property,
        checkin_date,
        checkout_date,
        guests_count,
        opts \\ []
      ) do
    hold_duration = Keyword.get(opts, :hold_duration_minutes, @hold_duration_minutes)
    hold_expires_at = DateTime.add(DateTime.utc_now(), hold_duration, :minute)

    Repo.transaction(fn ->
      days = Date.range(checkin_date, Date.add(checkout_date, -1)) |> Enum.to_list()

      # Ensure property_inventory rows exist with capacity_total = season cap (e.g., 12)
      for day <- days do
        capacity_total = get_property_capacity_for_date(property, day)
        ensure_property_inventory_row(property, day, capacity_total)
      end

      # Lock property_inventory rows FOR UPDATE
      locked_prop_inv =
        Repo.all(
          from pi in PropertyInventory,
            where:
              pi.property == ^property and pi.day >= ^checkin_date and pi.day < ^checkout_date,
            lock: "FOR UPDATE"
        )

      # Validate for each day: buyout flags false and capacity_booked + capacity_held + guests <= capacity_total
      invalid_days =
        Enum.filter(locked_prop_inv, fn pi ->
          pi.buyout_held == true or
            pi.buyout_booked == true or
            pi.capacity_booked + pi.capacity_held + guests_count > pi.capacity_total
        end)

      if length(invalid_days) > 0 do
        Repo.rollback({:error, :insufficient_capacity})
      end

      # Increment capacity_held
      {count, _} =
        Repo.update_all(
          from(pi in PropertyInventory,
            where:
              pi.property == ^property and pi.day >= ^checkin_date and pi.day < ^checkout_date
          ),
          inc: [capacity_held: guests_count],
          set: [updated_at: DateTime.truncate(DateTime.utc_now(), :second)]
        )

      if count == 0 do
        Repo.rollback({:error, :inventory_update_failed})
      end

      # Create booking :hold
      # Calculate pricing
      {total_price, pricing_items} =
        case Bookings.calculate_booking_price(
               property,
               checkin_date,
               checkout_date,
               :day,
               nil,
               guests_count,
               0
             ) do
          {:ok, total} ->
            nights = Date.diff(checkout_date, checkin_date)

            price_per_guest_per_night =
              if nights > 0 and guests_count > 0 do
                Money.div(total, nights * guests_count) |> elem(1)
              else
                Money.new(0, :USD)
              end

            items = %{
              "type" => "per_guest",
              "nights" => nights,
              "guests_count" => guests_count,
              "price_per_guest_per_night" => %{
                "amount" => Decimal.to_string(price_per_guest_per_night.amount),
                "currency" => Atom.to_string(price_per_guest_per_night.currency)
              },
              "total" => %{
                "amount" => Decimal.to_string(total.amount),
                "currency" => Atom.to_string(total.currency)
              }
            }

            {total, items}

          {:error, _reason} ->
            {nil, nil}
        end

      attrs = %{
        property: property,
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        booking_mode: :day,
        guests_count: guests_count,
        user_id: user_id,
        status: :hold,
        hold_expires_at: hold_expires_at,
        total_price: total_price,
        pricing_items: pricing_items
      }

      case %Booking{}
           |> Booking.changeset(attrs, skip_validation: true)
           |> Repo.insert() do
        {:ok, booking} ->
          booking

        {:error, changeset} ->
          Repo.rollback({:error, changeset})
      end
    end)
  end

  @doc """
  Confirms a booking (moves from :hold to :complete) and updates inventory accordingly.

  ## Parameters:
  - `booking_id`: The booking to confirm

  ## Returns:
  - `{:ok, %Booking{}}` on success
  - `{:error, reason}` on failure
  """
  def confirm_booking(booking_id) do
    Repo.transaction(fn ->
      booking = Repo.get!(Booking, booking_id)

      if booking.status != :hold do
        Repo.rollback({:error, :invalid_status})
      end

      case booking.booking_mode do
        :buyout ->
          # Flip to buyout_booked = true
          {count, _} =
            Repo.update_all(
              from(pi in PropertyInventory,
                where:
                  pi.property == ^booking.property and
                    pi.day >= ^booking.checkin_date and pi.day < ^booking.checkout_date
              ),
              set: [
                buyout_held: false,
                buyout_booked: true,
                updated_at: DateTime.truncate(DateTime.utc_now(), :second)
              ]
            )

          if count == 0 do
            Repo.rollback({:error, :inventory_update_failed})
          end

        :room ->
          # Set booked = true, clear held
          {count, _} =
            Repo.update_all(
              from(ri in RoomInventory,
                where:
                  ri.room_id == ^booking.room_id and
                    ri.day >= ^booking.checkin_date and ri.day < ^booking.checkout_date
              ),
              set: [
                held: false,
                booked: true,
                updated_at: DateTime.truncate(DateTime.utc_now(), :second)
              ]
            )

          if count == 0 do
            Repo.rollback({:error, :inventory_update_failed})
          end

        :day ->
          # Decrement held, increment booked
          {count, _} =
            Repo.update_all(
              from(pi in PropertyInventory,
                where:
                  pi.property == ^booking.property and
                    pi.day >= ^booking.checkin_date and pi.day < ^booking.checkout_date
              ),
              inc: [
                capacity_booked: booking.guests_count,
                capacity_held: -booking.guests_count
              ],
              set: [updated_at: DateTime.truncate(DateTime.utc_now(), :second)]
            )

          if count == 0 do
            Repo.rollback({:error, :inventory_update_failed})
          end
      end

      # Update booking status
      case booking
           |> Booking.changeset(%{status: :complete, hold_expires_at: nil}, skip_validation: true)
           |> Repo.update() do
        {:ok, updated_booking} ->
          updated_booking

        {:error, changeset} ->
          Repo.rollback({:error, changeset})
      end
    end)
  end

  @doc """
  Releases a hold (cancels a :hold booking) and updates inventory accordingly.

  ## Parameters:
  - `booking_id`: The booking to release

  ## Returns:
  - `{:ok, %Booking{}}` on success
  - `{:error, reason}` on failure
  """
  def release_hold(booking_id) do
    Repo.transaction(fn ->
      booking = Repo.get!(Booking, booking_id)

      if booking.status != :hold do
        Repo.rollback({:error, :invalid_status})
      end

      case booking.booking_mode do
        :buyout ->
          # Reset buyout_held = false
          {count, _} =
            Repo.update_all(
              from(pi in PropertyInventory,
                where:
                  pi.property == ^booking.property and
                    pi.day >= ^booking.checkin_date and pi.day < ^booking.checkout_date
              ),
              set: [
                buyout_held: false,
                updated_at: DateTime.truncate(DateTime.utc_now(), :second)
              ]
            )

          if count == 0 do
            Repo.rollback({:error, :inventory_update_failed})
          end

        :room ->
          # Clear held
          {count, _} =
            Repo.update_all(
              from(ri in RoomInventory,
                where:
                  ri.room_id == ^booking.room_id and
                    ri.day >= ^booking.checkin_date and ri.day < ^booking.checkout_date
              ),
              set: [held: false, updated_at: DateTime.truncate(DateTime.utc_now(), :second)]
            )

          if count == 0 do
            Repo.rollback({:error, :inventory_update_failed})
          end

        :day ->
          # Decrement held
          {count, _} =
            Repo.update_all(
              from(pi in PropertyInventory,
                where:
                  pi.property == ^booking.property and
                    pi.day >= ^booking.checkin_date and pi.day < ^booking.checkout_date
              ),
              inc: [capacity_held: -booking.guests_count],
              set: [updated_at: DateTime.truncate(DateTime.utc_now(), :second)]
            )

          if count == 0 do
            Repo.rollback({:error, :inventory_update_failed})
          end
      end

      # Update booking status to canceled
      case booking
           |> Booking.changeset(%{status: :canceled, hold_expires_at: nil}, skip_validation: true)
           |> Repo.update() do
        {:ok, updated_booking} ->
          updated_booking

        {:error, changeset} ->
          Repo.rollback({:error, changeset})
      end
    end)
  end

  ## Private Functions

  defp ensure_property_inventory_row(property, day, capacity_total) do
    Repo.insert_all(
      PropertyInventory,
      [
        %{
          property: property,
          day: day,
          capacity_total: capacity_total,
          capacity_held: 0,
          capacity_booked: 0,
          buyout_held: false,
          buyout_booked: false,
          updated_at: DateTime.truncate(DateTime.utc_now(), :second)
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:property, :day]
    )
  end

  defp ensure_room_inventory_row(room_id, day) do
    Repo.insert_all(
      RoomInventory,
      [
        %{
          room_id: room_id,
          day: day,
          held: false,
          booked: false,
          updated_at: DateTime.truncate(DateTime.utc_now(), :second)
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:room_id, :day]
    )
  end

  defp build_room_pricing_items(room, total, nights, guests_count, children_count) do
    # For room bookings, we'll create a simplified structure
    # The actual per-night breakdown would require more detailed calculation
    %{
      "type" => "room",
      "room_id" => room.id,
      "room_name" => room.name,
      "nights" => nights,
      "guests_count" => guests_count,
      "children_count" => children_count,
      "total" => %{
        "amount" => Decimal.to_string(total.amount),
        "currency" => Atom.to_string(total.currency)
      }
    }
  end

  defp get_property_capacity_for_date(property, _date) do
    # TODO: Get from season policy if available
    # For now, use defaults
    case property do
      :clear_lake -> @default_capacity_clear_lake
      :tahoe -> @default_capacity_tahoe
      _ -> 0
    end
  end
end
