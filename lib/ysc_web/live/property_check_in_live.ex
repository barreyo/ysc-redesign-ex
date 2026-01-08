defmodule YscWeb.PropertyCheckInLive do
  use YscWeb, :live_view
  use YscNative, :live_view

  # Step states
  @step_welcome :welcome
  @step_reservation :reservation
  @step_guests :guests
  @step_vehicle :vehicle
  @step_overview :overview
  @step_success :success

  # Dummy data
  @dummy_reservation %{
    number: "RES-2024-001",
    property_name: "Mountain View Retreat",
    wifi_password: "Welcome2024!",
    guests: [
      %{
        id: 1,
        first_name: "Jane",
        last_name: "Doe",
        room: "Master Suite",
        arrived: false,
        is_primary: true
      },
      %{
        id: 2,
        first_name: "John",
        last_name: "Smith",
        room: "Guest Room A",
        arrived: false,
        is_primary: true
      },
      %{
        id: 3,
        first_name: "Sarah",
        last_name: "Johnson",
        room: "Master Suite",
        arrived: false,
        is_primary: false
      },
      %{
        id: 4,
        first_name: "Mike",
        last_name: "Williams",
        room: "The Loft",
        arrived: false,
        is_primary: true
      }
    ],
    rooms: [
      %{name: "Master Suite", primary_guest: "Jane Doe", guest_count: 2, vehicles: []},
      %{name: "Guest Room A", primary_guest: "John Smith", guest_count: 1, vehicles: []},
      %{name: "The Loft", primary_guest: "Mike Williams", guest_count: 1, vehicles: []}
    ]
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:step, @step_welcome)
     |> assign(:reservation_number, "")
     |> assign(:reservation, nil)
     |> assign(:current_vehicle, %{plate: "", color: "", type: ""})
     |> assign(:vehicles, [])}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("start_check_in", _params, socket) do
    {:noreply, assign(socket, :step, @step_reservation)}
  end

  def handle_event("submit_reservation", params, socket) do
    number = Map.get(params, "reservation_number", socket.assigns.reservation_number)

    # In real app, this would look up the reservation
    # For now, use dummy data if number matches or any non-empty string
    reservation = if String.trim(number) != "", do: @dummy_reservation, else: nil

    socket =
      if reservation do
        socket
        |> assign(:reservation, reservation)
        |> assign(:reservation_number, number)
        |> assign(:step, @step_guests)
      else
        socket
        |> assign(:reservation_number, number)
        |> put_flash(:error, "Reservation not found. Please check your reservation number.")
      end

    {:noreply, socket}
  end

  def handle_event("update_reservation_number", params, socket) do
    number = Map.get(params, "reservation_number", socket.assigns.reservation_number)
    {:noreply, assign(socket, :reservation_number, number)}
  end

  def handle_event("toggle_guest_arrived", %{"guest_id" => id_str}, socket) do
    guest_id = String.to_integer(id_str)
    reservation = socket.assigns.reservation

    updated_guests =
      Enum.map(reservation.guests, fn guest ->
        if guest.id == guest_id do
          Map.update!(guest, :arrived, &(!&1))
        else
          guest
        end
      end)

    updated_reservation = Map.put(reservation, :guests, updated_guests)

    {:noreply, assign(socket, :reservation, updated_reservation)}
  end

  def handle_event("continue_to_vehicle", _params, socket) do
    {:noreply, assign(socket, :step, @step_vehicle)}
  end

  def handle_event("update_vehicle_field", params, socket) do
    field = Map.get(params, "field", "")
    value = Map.get(params, "value", "")
    plate = Map.get(params, "plate", socket.assigns.current_vehicle.plate)

    current_vehicle = socket.assigns.current_vehicle

    updated_vehicle =
      cond do
        field == "plate" or Map.has_key?(params, "plate") ->
          Map.put(current_vehicle, :plate, plate)

        field == "color" ->
          Map.put(current_vehicle, :color, value)

        field == "type" ->
          Map.put(current_vehicle, :type, value)

        true ->
          current_vehicle
      end

    {:noreply, assign(socket, :current_vehicle, updated_vehicle)}
  end

  def handle_event("add_vehicle", _params, socket) do
    vehicle = socket.assigns.current_vehicle

    if vehicle.plate != "" do
      new_vehicle = %{
        plate: vehicle.plate,
        color: vehicle.color,
        type: vehicle.type
      }

      {:noreply,
       socket
       |> assign(:vehicles, socket.assigns.vehicles ++ [new_vehicle])
       |> assign(:current_vehicle, %{plate: "", color: "", type: ""})
       |> assign(:step, @step_overview)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("skip_vehicle", _params, socket) do
    {:noreply, assign(socket, :step, @step_overview)}
  end

  def handle_event("complete_check_in", _params, socket) do
    {:noreply, assign(socket, :step, @step_success)}
  end

  def handle_event("start_over", _params, socket) do
    {:noreply,
     socket
     |> assign(:step, @step_welcome)
     |> assign(:reservation_number, "")
     |> assign(:reservation, nil)
     |> assign(:current_vehicle, %{plate: "", color: "", type: ""})
     |> assign(:vehicles, [])}
  end
end
