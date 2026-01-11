defmodule YscWeb.TahoeStayingWithLive do
  use YscWeb, :live_view
  use YscNative, :live_view

  alias Ysc.Bookings

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()
    start_date = Date.add(today, -2)
    end_date = Date.add(today, 14)

    # Generate calendar dates
    calendar_dates = Date.range(start_date, end_date) |> Enum.to_list()

    # Fetch rooms for Tahoe property
    rooms =
      Bookings.list_rooms(:tahoe)
      |> Enum.filter(& &1.is_active)
      |> Enum.sort_by(& &1.name)

    # Fetch bookings for Tahoe property in date range
    bookings =
      Bookings.list_bookings(:tahoe, start_date, end_date,
        preload: [:rooms, :user, check_ins: :check_in_vehicles]
      )
      |> Enum.filter(fn booking ->
        booking.status != :canceled && booking.status != :refunded
      end)
      |> Enum.filter(fn booking ->
        # Only include room bookings (not buyout bookings)
        Ecto.assoc_loaded?(booking.rooms) && length(booking.rooms) > 0
      end)

    # Group bookings by room
    bookings_by_room =
      bookings
      |> Enum.reduce(%{}, fn booking, acc ->
        Enum.reduce(booking.rooms, acc, fn room, room_acc ->
          booking_data = %{
            id: booking.id,
            user_name: format_user_name(booking.user),
            checkin_date: booking.checkin_date,
            checkout_date: booking.checkout_date,
            checked_in: booking.checked_in || false,
            car_info: format_car_info(booking.check_ins)
          }

          Map.update(room_acc, room.id, [booking_data], fn existing ->
            [booking_data | existing]
          end)
        end)
      end)

    # Format data for Swift component
    calendar_data_json =
      format_calendar_data(rooms, calendar_dates, bookings_by_room, today, start_date, end_date)

    # Ensure we have valid JSON
    if calendar_data_json == nil || calendar_data_json == "" do
      require Logger
      Logger.error("[TahoeStayingWithLive] Failed to generate calendar_data_json")
    end

    socket =
      socket
      |> assign(:calendar_data_json, calendar_data_json)

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  defp format_user_name(user) do
    cond do
      user.first_name && user.last_name ->
        "#{user.first_name} #{user.last_name}"

      user.first_name ->
        user.first_name

      user.last_name ->
        user.last_name

      user.email ->
        user.email

      true ->
        "Guest"
    end
  end

  defp format_car_info(check_ins) when is_list(check_ins) do
    check_ins
    |> Enum.filter(fn check_in ->
      Ecto.assoc_loaded?(check_in.check_in_vehicles) && length(check_in.check_in_vehicles) > 0
    end)
    |> Enum.flat_map(fn check_in ->
      Enum.map(check_in.check_in_vehicles, fn vehicle ->
        parts = [vehicle.make, vehicle.type, vehicle.color]
        parts = Enum.filter(parts, &(&1 && &1 != ""))
        Enum.join(parts, " ")
      end)
    end)
    |> case do
      [] -> nil
      [car_info] -> car_info
      car_infos -> Enum.join(car_infos, ", ")
    end
  end

  defp format_car_info(_), do: nil

  defp format_calendar_data(rooms, calendar_dates, bookings_by_room, today, start_date, end_date) do
    # Convert dates to ISO8601 strings
    date_to_string = fn date -> Date.to_iso8601(date) end

    # Format rooms - convert ULID to string for JSON
    formatted_rooms =
      Enum.map(rooms, fn room ->
        %{
          id: to_string(room.id),
          name: room.name
        }
      end)

    # Format calendar dates
    formatted_dates = Enum.map(calendar_dates, date_to_string)

    # Format bookings by room - convert ULID room_id to string
    formatted_bookings_by_room =
      bookings_by_room
      |> Enum.map(fn {room_id, bookings} ->
        formatted_bookings =
          Enum.map(bookings, fn booking ->
            %{
              id: to_string(booking.id),
              userName: booking.user_name,
              checkinDate: date_to_string.(booking.checkin_date),
              checkoutDate: date_to_string.(booking.checkout_date),
              checkedIn: booking.checked_in,
              carInfo: booking.car_info
            }
          end)

        # Convert room_id (ULID) to string for map key
        room_id_str = if is_binary(room_id), do: room_id, else: to_string(room_id)
        {room_id_str, formatted_bookings}
      end)
      |> Map.new()

    # Build the data structure
    calendar_data = %{
      rooms: formatted_rooms,
      calendarDates: formatted_dates,
      bookingsByRoom: formatted_bookings_by_room,
      today: date_to_string.(today),
      calendarStartDate: date_to_string.(start_date),
      calendarEndDate: date_to_string.(end_date)
    }

    # Encode to JSON
    Jason.encode!(calendar_data)
  end
end
