defmodule YscWeb.TahoeBookingLive do
  use YscWeb, :live_view

  alias Ysc.Bookings
  alias Ysc.Bookings.Season
  alias Ysc.MoneyHelper
  alias Ysc.Accounts

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if is_nil(user) do
      {:ok,
       socket
       |> put_flash(:error, "You must be logged in to make a booking")
       |> push_navigate(to: ~p"/users/log-in")}
    else
      # Load user with subscriptions for validation
      user_with_subs =
        Accounts.get_user!(user.id)
        |> Ysc.Repo.preload(:subscriptions)

      today = Date.utc_today()

      {:ok,
       assign(socket,
         page_title: "Book Tahoe Cabin",
         property: :tahoe,
         user: user_with_subs,
         checkin_date: nil,
         checkout_date: nil,
         selected_room_id: nil,
         selected_booking_mode: :room,
         guests_count: 1,
         children_count: 0,
         available_rooms: [],
         calculated_price: nil,
         price_error: nil,
         form_errors: %{},
         today: today
       )}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8 lg:py-10">
      <div class="space-y-8">
        <div>
          <h1 class="text-3xl font-bold text-zinc-900">Book Tahoe Cabin</h1>
          <p class="text-zinc-600 mt-2">
            Select your dates and room to make a reservation at our Lake Tahoe cabin.
          </p>
        </div>

        <.flash_group flash={@flash} />

        <div class="bg-white rounded-lg border border-zinc-200 p-6 space-y-6">
          <!-- Date Selection -->
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label class="block text-sm font-semibold text-zinc-700 mb-2">
                Check-in Date
              </label>
              <input
                type="date"
                phx-change="date-changed"
                phx-debounce="300"
                name="checkin_date"
                value={if @checkin_date, do: Date.to_string(@checkin_date), else: ""}
                min={Date.to_string(@today)}
                class="w-full px-3 py-2 border border-zinc-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
              />
              <p :if={@form_errors[:checkin_date]} class="text-red-600 text-sm mt-1">
                <%= @form_errors[:checkin_date] %>
              </p>
            </div>

            <div>
              <label class="block text-sm font-semibold text-zinc-700 mb-2">
                Check-out Date
              </label>
              <input
                type="date"
                phx-change="date-changed"
                phx-debounce="300"
                name="checkout_date"
                value={if @checkout_date, do: Date.to_string(@checkout_date), else: ""}
                min={
                  if @checkin_date, do: Date.to_string(@checkin_date), else: Date.to_string(@today)
                }
                class="w-full px-3 py-2 border border-zinc-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
              />
              <p :if={@form_errors[:checkout_date]} class="text-red-600 text-sm mt-1">
                <%= @form_errors[:checkout_date] %>
              </p>
            </div>
          </div>
          <!-- Booking Mode Selection (Summer only) -->
          <div :if={can_select_booking_mode?(@checkin_date)}>
            <label class="block text-sm font-semibold text-zinc-700 mb-2">
              Booking Type
            </label>
            <div class="flex gap-4">
              <label class="flex items-center">
                <input
                  type="radio"
                  name="booking_mode"
                  value="room"
                  checked={@selected_booking_mode == :room}
                  phx-change="booking-mode-changed"
                  class="mr-2"
                />
                <span>Individual Room</span>
              </label>
              <label class="flex items-center">
                <input
                  type="radio"
                  name="booking_mode"
                  value="buyout"
                  checked={@selected_booking_mode == :buyout}
                  phx-change="booking-mode-changed"
                  class="mr-2"
                />
                <span>Full Buyout</span>
              </label>
            </div>
          </div>
          <!-- Room Selection (for room bookings) -->
          <div :if={@selected_booking_mode == :room && @checkin_date && @checkout_date}>
            <label class="block text-sm font-semibold text-zinc-700 mb-2">
              Select Room
            </label>
            <div :if={Enum.empty?(@available_rooms)} class="text-zinc-600 text-sm">
              No rooms available for the selected dates.
            </div>
            <div :if={!Enum.empty?(@available_rooms)} class="space-y-2">
              <%= for room <- @available_rooms do %>
                <label class="flex items-center p-3 border border-zinc-300 rounded-md hover:bg-zinc-50 cursor-pointer">
                  <input
                    type="radio"
                    name="room_id"
                    value={room.id}
                    checked={@selected_room_id == room.id}
                    phx-change="room-changed"
                    class="mr-3"
                  />
                  <div class="flex-1">
                    <div class="font-medium text-zinc-900"><%= room.name %></div>
                    <div class="text-sm text-zinc-600">
                      <%= room.description %>
                      <span class="ml-2">• Max <%= room.capacity_max %> guests</span>
                      <span :if={room.min_billable_occupancy > 1} class="ml-2">
                        • Minimum <%= room.min_billable_occupancy %> guests
                      </span>
                    </div>
                  </div>
                </label>
              <% end %>
            </div>
            <p :if={@form_errors[:room_id]} class="text-red-600 text-sm mt-1">
              <%= @form_errors[:room_id] %>
            </p>
          </div>
          <!-- Guests Count -->
          <div :if={@selected_booking_mode == :room && @selected_room_id}>
            <label class="block text-sm font-semibold text-zinc-700 mb-2">
              Number of Adults
            </label>
            <input
              type="number"
              min="1"
              max={
                if @selected_room_id do
                  room = Enum.find(@available_rooms, &(&1.id == @selected_room_id))
                  if room, do: room.capacity_max, else: 1
                else
                  1
                end
              }
              value={@guests_count}
              phx-change="guests-changed"
              phx-debounce="300"
              class="w-full px-3 py-2 border border-zinc-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
            />
            <p :if={@form_errors[:guests_count]} class="text-red-600 text-sm mt-1">
              <%= @form_errors[:guests_count] %>
            </p>
          </div>

          <!-- Children Count (for Tahoe) -->
          <div :if={@selected_booking_mode == :room && @selected_room_id}>
            <label class="block text-sm font-semibold text-zinc-700 mb-2">
              Number of Children (ages 5-17)
            </label>
            <input
              type="number"
              min="0"
              value={@children_count}
              phx-change="children-changed"
              phx-debounce="300"
              class="w-full px-3 py-2 border border-zinc-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
            />
            <p class="text-sm text-zinc-600 mt-1">
              Children 5-17 years: $25/night. Children under 5 stay for free.
            </p>
          </div>
          <!-- Price Display -->
          <div :if={@calculated_price} class="bg-zinc-50 rounded-md p-4">
            <div class="flex justify-between items-center">
              <span class="text-lg font-semibold text-zinc-900">Total Price:</span>
              <span class="text-2xl font-bold text-blue-600">
                <%= MoneyHelper.format_money!(@calculated_price) %>
              </span>
            </div>
            <p :if={@checkin_date && @checkout_date} class="text-sm text-zinc-600 mt-2">
              <%= Date.diff(@checkout_date, @checkin_date) %> night(s)
            </p>
          </div>

          <p :if={@price_error} class="text-red-600 text-sm">
            <%= @price_error %>
          </p>
          <!-- Booking Rules Info -->
          <div class="bg-blue-50 border border-blue-200 rounded-md p-4">
            <h3 class="font-semibold text-blue-900 mb-2">Booking Rules for Tahoe:</h3>
            <ul class="text-sm text-blue-800 space-y-1 list-disc list-inside">
              <li>Check-in: 3:00 PM | Check-out: 11:00 AM</li>
              <li>Maximum 4 nights per booking</li>
              <li>If booking contains Saturday, must also include Sunday</li>
              <li>Winter: Only individual rooms allowed</li>
              <li>Summer: Individual rooms or full buyout available</li>
              <li>Winter: Only one active booking per user at a time</li>
              <li>Children 5-17 years: $25/night. Children under 5 stay for free.</li>
            </ul>
          </div>
          <!-- Submit Button -->
          <div>
            <button
              :if={
                can_submit_booking?(
                  @selected_booking_mode,
                  @checkin_date,
                  @checkout_date,
                  @selected_room_id
                )
              }
              phx-click="create-booking"
              class="w-full bg-blue-600 hover:bg-blue-700 text-white font-semibold py-3 px-4 rounded-md transition duration-200"
            >
              Create Booking
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event(
        "date-changed",
        %{"checkin_date" => checkin_date_str, "checkout_date" => checkout_date_str},
        socket
      ) do
    checkin_date = parse_date(checkin_date_str)
    checkout_date = parse_date(checkout_date_str)

    socket =
      socket
      |> assign(
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        selected_room_id: nil,
        available_rooms: [],
        calculated_price: nil,
        price_error: nil,
        form_errors: %{}
      )
      |> update_available_rooms()
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  def handle_event("date-changed", %{"checkin_date" => checkin_date_str}, socket) do
    checkin_date = parse_date(checkin_date_str)

    socket =
      socket
      |> assign(
        checkin_date: checkin_date,
        selected_room_id: nil,
        available_rooms: [],
        calculated_price: nil,
        price_error: nil,
        form_errors: %{}
      )
      |> update_available_rooms()
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  def handle_event("date-changed", %{"checkout_date" => checkout_date_str}, socket) do
    checkout_date = parse_date(checkout_date_str)
    # Preserve existing checkin_date
    checkin_date = socket.assigns.checkin_date

    socket =
      socket
      |> assign(
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        selected_room_id: nil,
        available_rooms: [],
        calculated_price: nil,
        price_error: nil,
        form_errors: %{}
      )
      |> update_available_rooms()
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  def handle_event("booking-mode-changed", %{"booking_mode" => "room"}, socket) do
    socket =
      socket
      |> assign(
        selected_booking_mode: :room,
        calculated_price: nil,
        price_error: nil
      )
      |> update_available_rooms()
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  def handle_event("booking-mode-changed", %{"booking_mode" => "buyout"}, socket) do
    socket =
      socket
      |> assign(
        selected_booking_mode: :buyout,
        selected_room_id: nil,
        available_rooms: [],
        calculated_price: nil,
        price_error: nil
      )
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  def handle_event("room-changed", %{"room_id" => room_id_str}, socket) do
    room_id = if room_id_str != "", do: room_id_str, else: nil

    socket =
      socket
      |> assign(selected_room_id: room_id, calculated_price: nil, price_error: nil)
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  def handle_event("guests-changed", %{"guests_count" => guests_str}, socket) do
    guests_count = parse_integer(guests_str) || 1

    socket =
      socket
      |> assign(guests_count: guests_count, calculated_price: nil, price_error: nil)
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  def handle_event("children-changed", %{"children_count" => children_str}, socket) do
    children_count = parse_integer(children_str) || 0

    socket =
      socket
      |> assign(children_count: children_count, calculated_price: nil, price_error: nil)
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  def handle_event("create-booking", _params, socket) do
    case validate_and_create_booking(socket) do
      {:ok, :created} ->
        {:noreply,
         socket
         |> put_flash(:info, "Booking created successfully!")
         |> push_navigate(to: ~p"/users/settings")}

      {:error, changeset} ->
        form_errors = format_errors(changeset)

        {:noreply,
         assign(socket,
           form_errors: form_errors,
           calculated_price: nil,
           price_error: "Please fix the errors above"
         )}
    end
  end

  # Helper functions

  defp parse_date(""), do: nil
  defp parse_date(date_str) when is_binary(date_str), do: Date.from_iso8601!(date_str)
  defp parse_date(_), do: nil

  defp parse_integer(""), do: nil
  defp parse_integer(int_str) when is_binary(int_str), do: String.to_integer(int_str)
  defp parse_integer(_), do: nil

  defp update_available_rooms(socket) do
    if socket.assigns.checkin_date && socket.assigns.checkout_date &&
         socket.assigns.selected_booking_mode == :room do
      available_rooms =
        Bookings.get_available_rooms(
          socket.assigns.property,
          socket.assigns.checkin_date,
          socket.assigns.checkout_date
        )

      assign(socket, available_rooms: available_rooms)
    else
      assign(socket, available_rooms: [])
    end
  end

  defp calculate_price_if_ready(socket) do
    if ready_for_price_calculation?(socket) do
      case Bookings.calculate_booking_price(
             socket.assigns.property,
             socket.assigns.checkin_date,
             socket.assigns.checkout_date,
             socket.assigns.selected_booking_mode,
             socket.assigns.selected_room_id,
             socket.assigns.guests_count,
             socket.assigns.children_count
           ) do
        {:ok, price} ->
          assign(socket, calculated_price: price, price_error: nil)

        {:error, reason} ->
          assign(socket,
            calculated_price: nil,
            price_error: "Unable to calculate price: #{inspect(reason)}"
          )
      end
    else
      assign(socket, calculated_price: nil, price_error: nil)
    end
  end

  defp ready_for_price_calculation?(socket) do
    socket.assigns.checkin_date &&
      socket.assigns.checkout_date &&
      (socket.assigns.selected_booking_mode == :buyout ||
         (socket.assigns.selected_booking_mode == :room && socket.assigns.selected_room_id))
  end

  defp can_select_booking_mode?(checkin_date) do
    if checkin_date do
      season = Season.for_date(:tahoe, checkin_date)
      season && season.name == "Summer"
    else
      false
    end
  end

  defp can_submit_booking?(booking_mode, checkin_date, checkout_date, room_id) do
    checkin_date && checkout_date &&
      (booking_mode == :buyout || (booking_mode == :room && room_id))
  end

  defp validate_and_create_booking(socket) do
    attrs = %{
      property: socket.assigns.property,
      checkin_date: socket.assigns.checkin_date,
      checkout_date: socket.assigns.checkout_date,
      booking_mode: socket.assigns.selected_booking_mode,
      room_id: socket.assigns.selected_room_id,
      guests_count: socket.assigns.guests_count,
      children_count: socket.assigns.children_count,
      user_id: socket.assigns.user.id
    }

    changeset = Bookings.Booking.changeset(%Bookings.Booking{}, attrs, user: socket.assigns.user)

    case Ysc.Repo.insert(changeset) do
      {:ok, _booking} -> {:ok, :created}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
