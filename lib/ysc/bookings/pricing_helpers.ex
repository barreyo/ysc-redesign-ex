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
    checkin_date = Map.get(socket.assigns, :checkin_date)
    checkout_date = Map.get(socket.assigns, :checkout_date)
    has_dates = !is_nil(checkin_date) && !is_nil(checkout_date)

    if not has_dates do
      false
    else
      booking_mode = Map.get(socket.assigns, :selected_booking_mode)

      case booking_mode do
        :buyout ->
          true

        :room ->
          # For Tahoe room bookings, need at least one room selected
          # Check both single room selection and multiple room selection
          selected_room_id = Map.get(socket.assigns, :selected_room_id)
          selected_room_ids = Map.get(socket.assigns, :selected_room_ids)

          !is_nil(selected_room_id) ||
            (!is_nil(selected_room_ids) && is_list(selected_room_ids) && selected_room_ids != [])

        :day ->
          # For Clear Lake day bookings, need guests count
          guests_count = Map.get(socket.assigns, :guests_count)
          !is_nil(guests_count) && is_integer(guests_count) && guests_count > 0

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

      guests_count = parse_guests_fn.(Map.get(socket.assigns, :guests_count, 1))
      children_count = parse_children_fn.(Map.get(socket.assigns, :children_count, 0))

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

      # Calculate minimum billable people across all selected rooms
      # This ensures we charge for at least the sum of minimum occupancies
      # Children count towards minimum occupancy, so we need to account for them
      billable_people =
        if room_count > 1 do
          # Multiple rooms: sum the min_billable_occupancy of all rooms
          # Use available_rooms from socket assigns if available, otherwise query
          available_rooms = socket.assigns[:available_rooms] || []

          room_minimums =
            room_ids
            |> Enum.map(fn room_id ->
              # Try to find room in available_rooms first (already loaded)
              # Convert both to strings for comparison to handle binary_id vs string mismatches
              room =
                Enum.find(available_rooms, fn r ->
                  to_string(r.id) == to_string(room_id)
                end) ||
                  try do
                    Bookings.get_room!(room_id)
                  rescue
                    _ -> nil
                  end

              case room do
                nil ->
                  # Default to 1 if room not found
                  1

                r ->
                  # Get min_billable_occupancy, defaulting to 1
                  Map.get(r, :min_billable_occupancy) || 1
              end
            end)

          # For multiple rooms, sum the individual room minimums
          # Each room must satisfy its own minimum, so we need enough people for all rooms combined
          total_min_occupancy =
            if Enum.empty?(room_minimums) do
              1
            else
              Enum.sum(room_minimums)
            end

          # Check if total people (adults + children) meets the total minimum across all rooms
          # If yes, charge only for actual adults. If no, charge for enough adults to meet minimum.
          total_people = guests_count + children_count

          if total_people >= total_min_occupancy do
            # Total people meets minimum, charge only for actual adults
            guests_count
          else
            # Total people doesn't meet minimum, need to charge for more adults
            min_adults_needed = max(0, total_min_occupancy - children_count)
            max(guests_count, min_adults_needed)
          end
        else
          # Single room: calculate billable people accounting for children
          room_id = List.first(room_ids)
          available_rooms = socket.assigns[:available_rooms] || []

          room =
            Enum.find(available_rooms, &(&1.id == room_id)) ||
              try do
                Bookings.get_room!(room_id)
              rescue
                _ -> nil
              end

          if room do
            min_occupancy = room.min_billable_occupancy || 1
            # If total people (adults + children) is less than minimum,
            # we need to charge for more adults to meet the minimum
            min_adults_needed = max(0, min_occupancy - children_count)
            max(guests_count, min_adults_needed)
          else
            guests_count
          end
        end

      case Bookings.calculate_booking_price(
             property,
             socket.assigns.checkin_date,
             socket.assigns.checkout_date,
             :room,
             List.first(room_ids),
             billable_people,
             children_count,
             nil,
             true
           ) do
        {:ok, price, breakdown} ->
          # Ensure billable_people is set correctly in the breakdown
          # This is important for display - it should reflect the minimum occupancy calculation
          # Check if minimum occupancy pricing is being applied (billable_people > actual guests_count)
          using_minimum_pricing = billable_people > guests_count

          final_breakdown =
            (breakdown || %{})
            |> Map.merge(%{
              room_count: room_count,
              guests_count: guests_count,
              billable_people: billable_people,
              children_count: children_count,
              using_minimum_pricing: using_minimum_pricing
            })
            # Explicitly set billable_people to ensure it's not overridden
            |> Map.put(:billable_people, billable_people)
            |> Map.put(:using_minimum_pricing, using_minimum_pricing)

          assign(socket,
            calculated_price: price,
            price_breakdown: final_breakdown,
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
      {:ok, price, breakdown} ->
        assign(socket,
          calculated_price: price,
          price_breakdown:
            Map.merge(breakdown || %{}, %{
              guests_count: guests_count
            }),
          price_error: nil
        )

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
