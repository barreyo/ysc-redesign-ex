defmodule Ysc.Bookings.PricingHelpers do
  @moduledoc """
  Shared helper functions for booking price calculations.

  Provides utilities for:
  - Checking if price calculation is ready
  - Calculating prices for different booking modes
  - Handling price breakdowns
  - Returning consistent socket assigns
  """

  alias Ysc.Bookings
  import Phoenix.Component, only: [assign: 2]

  @doc """
  Checks if the socket has all required information to calculate a price.

  ## Parameters
  - `socket`: The LiveView socket
  - `property`: The property type (:tahoe or :clear_lake)

  ## Returns
  - `true` if ready to calculate price
  - `false` otherwise
  """
  def ready_for_price_calculation?(socket, _property) do
    has_dates = socket.assigns.checkin_date && socket.assigns.checkout_date

    if not has_dates do
      false
    else
      case socket.assigns.selected_booking_mode do
        :buyout ->
          true

        :room ->
          # For Tahoe room bookings, need at least one room selected
          # Check both single room selection and multiple room selection
          socket.assigns.selected_room_id ||
            (socket.assigns.selected_room_ids && socket.assigns.selected_room_ids != [])

        :day ->
          # For Clear Lake day bookings, need guests count
          socket.assigns.guests_count && socket.assigns.guests_count > 0

        _ ->
          false
      end
    end
  end

  @doc """
  Calculates the booking price and returns a function that updates the socket.

  Handles different booking modes:
  - `:buyout` - Full cabin buyout
  - `:room` - Individual room(s) booking (Tahoe)
  - `:day` - Per guest per day booking (Clear Lake)

  ## Parameters
  - `socket`: The LiveView socket
  - `property`: The property type (:tahoe or :clear_lake)
  - `opts`: Optional keyword list with:
    - `parse_guests_fn`: Function to parse guests count (default: identity)
    - `parse_children_fn`: Function to parse children count (default: identity)
    - `can_select_multiple_rooms_fn`: Function to check if multiple rooms allowed (default: always false)

  ## Returns
  - Updated socket with `calculated_price`, `price_breakdown`, and `price_error` assigns
  """
  def calculate_price_if_ready(socket, property, opts \\ []) do
    if ready_for_price_calculation?(socket, property) do
      parse_guests_fn = Keyword.get(opts, :parse_guests_fn, &Function.identity/1)
      parse_children_fn = Keyword.get(opts, :parse_children_fn, &Function.identity/1)

      can_select_multiple_rooms_fn =
        Keyword.get(opts, :can_select_multiple_rooms_fn, fn _ -> false end)

      guests_count = parse_guests_fn.(socket.assigns.guests_count || 1)
      children_count = parse_children_fn.(socket.assigns.children_count || 0)

      case socket.assigns.selected_booking_mode do
        :buyout ->
          calculate_buyout_price(socket, property, guests_count, children_count)

        :room ->
          calculate_room_price(
            socket,
            property,
            guests_count,
            children_count,
            can_select_multiple_rooms_fn
          )

        :day ->
          calculate_day_price(socket, property, guests_count)

        _ ->
          assign_error(socket, "Invalid booking mode")
      end
    else
      assign(socket, calculated_price: nil, price_breakdown: nil, price_error: nil)
    end
  end

  # Calculate price for buyout mode
  defp calculate_buyout_price(socket, property, guests_count, children_count) do
    case Bookings.calculate_booking_price(
           property,
           socket.assigns.checkin_date,
           socket.assigns.checkout_date,
           :buyout,
           nil,
           guests_count,
           children_count
         ) do
      {:ok, price, breakdown} ->
        assign(socket,
          calculated_price: price,
          price_breakdown:
            Map.merge(breakdown || %{}, %{
              guests_count: guests_count,
              children_count: children_count
            }),
          price_error: nil
        )

      {:ok, price} ->
        assign(socket,
          calculated_price: price,
          price_breakdown: nil,
          price_error: nil
        )

      {:error, reason} ->
        assign_error(socket, "Unable to calculate price: #{inspect(reason)}")
    end
  end

  # Calculate price for room mode (Tahoe)
  defp calculate_room_price(
         socket,
         property,
         guests_count,
         children_count,
         can_select_multiple_rooms_fn
       ) do
    room_ids =
      if can_select_multiple_rooms_fn.(socket.assigns) do
        socket.assigns.selected_room_ids || []
      else
        if socket.assigns.selected_room_id, do: [socket.assigns.selected_room_id], else: []
      end

    if room_ids == [] do
      assign_error(socket, "Please select at least one room")
    else
      # For multiple rooms, calculate price once for total guests (not per room)
      # Use the first room to get pricing rules, but calculate for total guests
      room_count = length(room_ids)

      case Bookings.calculate_booking_price(
             property,
             socket.assigns.checkin_date,
             socket.assigns.checkout_date,
             :room,
             List.first(room_ids),
             guests_count,
             children_count,
             nil,
             true
           ) do
        {:ok, price, breakdown} ->
          assign(socket,
            calculated_price: price,
            price_breakdown:
              Map.merge(breakdown || %{}, %{
                room_count: room_count,
                guests_count: guests_count,
                children_count: children_count
              }),
            price_error: nil
          )

        {:ok, price} ->
          assign(socket,
            calculated_price: price,
            price_breakdown: nil,
            price_error: nil
          )

        {:error, reason} ->
          assign_error(socket, "Unable to calculate price: #{inspect(reason)}")
      end
    end
  end

  # Calculate price for day mode (Clear Lake)
  defp calculate_day_price(socket, property, guests_count) do
    case Bookings.calculate_booking_price(
           property,
           socket.assigns.checkin_date,
           socket.assigns.checkout_date,
           :day,
           nil,
           guests_count
         ) do
      {:ok, price} ->
        assign(socket, calculated_price: price, price_breakdown: nil, price_error: nil)

      {:error, reason} ->
        assign_error(socket, "Unable to calculate price: #{inspect(reason)}")
    end
  end

  # Helper to assign error state
  defp assign_error(socket, error_message) do
    assign(socket,
      calculated_price: nil,
      price_breakdown: nil,
      price_error: error_message
    )
  end
end
