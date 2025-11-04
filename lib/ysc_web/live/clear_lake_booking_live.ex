defmodule YscWeb.ClearLakeBookingLive do
  use YscWeb, :live_view

  alias Ysc.Bookings
  alias Ysc.MoneyHelper
  alias Ysc.Accounts

  @max_guests 12

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
         page_title: "Book Clear Lake Cabin",
         property: :clear_lake,
         user: user_with_subs,
         checkin_date: nil,
         checkout_date: nil,
         selected_booking_mode: :day,
         guests_count: 1,
         max_guests: @max_guests,
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
          <h1 class="text-3xl font-bold text-zinc-900">Book Clear Lake Cabin</h1>
          <p class="text-zinc-600 mt-2">
            Select your dates and number of guests to make a reservation at our Clear Lake cabin.
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
          <!-- Booking Mode Selection -->
          <div>
            <label class="block text-sm font-semibold text-zinc-700 mb-2">
              Booking Type
            </label>
            <div class="flex gap-4">
              <label class="flex items-center">
                <input
                  type="radio"
                  name="booking_mode"
                  value="day"
                  checked={@selected_booking_mode == :day}
                  phx-change="booking-mode-changed"
                  class="mr-2"
                />
                <span>Day Booking (per guest)</span>
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
          <!-- Guests Count (for day bookings) -->
          <div :if={@selected_booking_mode == :day}>
            <label class="block text-sm font-semibold text-zinc-700 mb-2">
              Number of Guests
            </label>
            <input
              type="number"
              min="1"
              max={@max_guests || 12}
              value={@guests_count}
              phx-change="guests-changed"
              phx-debounce="300"
              class="w-full px-3 py-2 border border-zinc-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
            />
            <p class="text-sm text-zinc-600 mt-1">
              Maximum <%= @max_guests %> guests per day
            </p>
            <p class="text-sm text-zinc-600 mt-1 italic">
              Note: Children up to and including 5 years old can join for free. Please do not include them when registering attendees.
            </p>
            <p :if={@form_errors[:guests_count]} class="text-red-600 text-sm mt-1">
              <%= @form_errors[:guests_count] %>
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
              <span :if={@selected_booking_mode == :day}>
                • <%= @guests_count %> guest(s)
              </span>
            </p>
          </div>

          <p :if={@price_error} class="text-red-600 text-sm">
            <%= @price_error %>
          </p>
          <!-- Booking Rules Info -->
          <div class="bg-blue-50 border border-blue-200 rounded-md p-4">
            <h3 class="font-semibold text-blue-900 mb-2">Booking Rules for Clear Lake:</h3>
            <ul class="text-sm text-blue-800 space-y-1 list-disc list-inside">
              <li>Check-in: 3:00 PM | Check-out: 11:00 AM</li>
              <li>Book by number of guests (not rooms)</li>
              <li>Priced per guest per day</li>
              <li>Maximum <%= @max_guests %> guests per day</li>
              <li>
                Children up to and including 5 years old can join for free (do not include in guest count)
              </li>
              <li>Option available for full buyout</li>
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
                  @guests_count
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
        calculated_price: nil,
        price_error: nil,
        form_errors: %{}
      )
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  def handle_event("date-changed", %{"checkin_date" => checkin_date_str}, socket) do
    checkin_date = parse_date(checkin_date_str)
    # Preserve existing checkout_date
    checkout_date = socket.assigns.checkout_date

    socket =
      socket
      |> assign(
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        calculated_price: nil,
        price_error: nil,
        form_errors: %{}
      )
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
        calculated_price: nil,
        price_error: nil,
        form_errors: %{}
      )
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  def handle_event("booking-mode-changed", %{"booking_mode" => "day"}, socket) do
    socket =
      socket
      |> assign(
        selected_booking_mode: :day,
        calculated_price: nil,
        price_error: nil
      )
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  def handle_event("booking-mode-changed", %{"booking_mode" => "buyout"}, socket) do
    socket =
      socket
      |> assign(
        selected_booking_mode: :buyout,
        calculated_price: nil,
        price_error: nil
      )
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

  defp calculate_price_if_ready(socket) do
    if ready_for_price_calculation?(socket) do
      case Bookings.calculate_booking_price(
             socket.assigns.property,
             socket.assigns.checkin_date,
             socket.assigns.checkout_date,
             socket.assigns.selected_booking_mode,
             nil,
             socket.assigns.guests_count
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
         (socket.assigns.selected_booking_mode == :day && socket.assigns.guests_count > 0))
  end

  defp can_submit_booking?(booking_mode, checkin_date, checkout_date, guests_count) do
    checkin_date && checkout_date &&
      (booking_mode == :buyout ||
         (booking_mode == :day && guests_count > 0 && guests_count <= @max_guests))
  end

  defp validate_and_create_booking(socket) do
    attrs = %{
      property: socket.assigns.property,
      checkin_date: socket.assigns.checkin_date,
      checkout_date: socket.assigns.checkout_date,
      booking_mode: socket.assigns.selected_booking_mode,
      room_id: nil,
      guests_count: socket.assigns.guests_count,
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
