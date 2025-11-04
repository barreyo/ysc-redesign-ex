defmodule YscWeb.TahoeBookingLive do
  use YscWeb, :live_view

  alias Ysc.Bookings
  alias Ysc.Bookings.{Season, Booking}
  alias Ysc.MoneyHelper
  alias Ysc.Accounts
  alias Ysc.Subscriptions
  alias Ysc.Repo
  require Logger
  import Ecto.Query

  @impl true
  def mount(params, _session, socket) do
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
      max_booking_date = Date.add(today, 45)

      # Parse query parameters, handling malformed/double-encoded URLs
      parsed_params = parse_mount_params(params)

      # Parse dates and guest counts from URL params if present
      {checkin_date, checkout_date} = parse_dates_from_params(parsed_params)
      guests_count = parse_guests_from_params(parsed_params)
      children_count = parse_children_from_params(parsed_params)

      date_form =
        to_form(
          %{
            "checkin_date" => date_to_datetime_string(checkin_date),
            "checkout_date" => date_to_datetime_string(checkout_date)
          },
          as: "booking_dates"
        )

      # Calculate membership type once and cache it
      membership_type = get_membership_type(user_with_subs)

      socket =
        assign(socket,
          page_title: "Book Tahoe Cabin",
          property: :tahoe,
          user: user_with_subs,
          checkin_date: checkin_date,
          checkout_date: checkout_date,
          today: today,
          max_booking_date: max_booking_date,
          selected_room_id: nil,
          selected_room_ids: [],
          selected_booking_mode: :room,
          guests_count: guests_count,
          children_count: children_count,
          guests_dropdown_open: false,
          available_rooms: [],
          calculated_price: nil,
          price_error: nil,
          form_errors: %{},
          date_validation_errors: %{},
          date_form: date_form,
          membership_type: membership_type
        )

      # If dates are present, initialize validation and room availability
      socket =
        if checkin_date && checkout_date do
          socket
          |> enforce_season_booking_mode()
          |> validate_dates()
          |> update_available_rooms()
          |> calculate_price_if_ready()
        else
          socket
        end

      {:ok, socket}
    end
  end

  @impl true
  def handle_params(params, uri, socket) do
    # Parse query parameters, handling malformed/double-encoded URLs
    params = parse_query_params(params, uri)

    # Parse dates and guest counts from URL params
    {checkin_date, checkout_date} = parse_dates_from_params(params)
    guests_count = parse_guests_from_params(params)
    children_count = parse_children_from_params(params)

    # Only update if dates or guest counts have changed
    if checkin_date != socket.assigns.checkin_date ||
         checkout_date != socket.assigns.checkout_date ||
         guests_count != socket.assigns.guests_count ||
         children_count != socket.assigns.children_count do
      today = Date.utc_today()
      max_booking_date = Date.add(today, 45)

      date_form =
        to_form(
          %{
            "checkin_date" => date_to_datetime_string(checkin_date),
            "checkout_date" => date_to_datetime_string(checkout_date)
          },
          as: "booking_dates"
        )

      socket =
        socket
        |> assign(
          checkin_date: checkin_date,
          checkout_date: checkout_date,
          today: today,
          max_booking_date: max_booking_date,
          guests_count: guests_count,
          children_count: children_count,
          selected_room_id: nil,
          selected_room_ids: [],
          guests_dropdown_open: false,
          available_rooms: [],
          calculated_price: nil,
          price_error: nil,
          form_errors: %{},
          date_form: date_form,
          date_validation_errors: %{}
        )
        |> enforce_season_booking_mode()
        |> validate_dates()
        |> update_available_rooms()
        |> calculate_price_if_ready()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:updated_event, %{start_date: start_date, end_date: end_date}}, socket) do
    checkin_date = if start_date, do: DateTime.to_date(start_date), else: nil
    checkout_date = if end_date, do: DateTime.to_date(end_date), else: nil

    date_form =
      to_form(
        %{
          "checkin_date" => date_to_datetime_string(checkin_date),
          "checkout_date" => date_to_datetime_string(checkout_date)
        },
        as: "booking_dates"
      )

    socket =
      socket
      |> assign(
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        selected_room_id: nil,
        selected_room_ids: [],
        available_rooms: [],
        calculated_price: nil,
        price_error: nil,
        form_errors: %{},
        date_form: date_form,
        date_validation_errors: %{}
      )
      |> enforce_season_booking_mode()
      |> validate_dates()
      |> update_available_rooms()
      |> calculate_price_if_ready()
      |> update_url_with_dates(checkin_date, checkout_date)

    {:noreply, socket}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="py-8 lg:py-10">
      <div class="max-w-screen-lg mx-auto flex flex-col px-4 space-y-6">
        <div class="prose prose-zinc">
          <h1>Book Tahoe Cabin</h1>
          <p>
            Select your dates and room(s) to make a reservation at our Lake Tahoe cabin.
          </p>
        </div>

        <.flash_group flash={@flash} />

        <div class="bg-white rounded-lg border border-zinc-200 p-6 space-y-6">
          <!-- Date Selection and Guest Counters (Inline) -->
          <div class="space-y-4">
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
              <!-- Date Selection -->
              <div class="md:col-span-1">
                <.date_range_picker
                  label="Check-in & Check-out Dates"
                  id="booking_date_range"
                  form={@date_form}
                  start_date_field={@date_form[:checkin_date]}
                  end_date_field={@date_form[:checkout_date]}
                  min={@today}
                  max={@max_booking_date}
                />
              </div>
              <!-- Guests and Children Selection (Dropdown) -->
              <div
                :if={@checkin_date && @checkout_date && @selected_booking_mode == :room}
                class="md:col-span-1 py-1 ms-0 md:ms-4"
              >
                <label class="block text-sm font-semibold text-zinc-700 mb-2">
                  Guests
                </label>
                <div class="relative">
                  <!-- Dropdown Trigger -->
                  <button
                    type="button"
                    phx-click="toggle-guests-dropdown"
                    class="w-full px-3 py-2 border border-zinc-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500 bg-white text-left flex items-center justify-between"
                  >
                    <span class="text-zinc-900">
                      <%= format_guests_display(@guests_count, @children_count) %>
                    </span>
                    <.icon
                      name={
                        if @guests_dropdown_open, do: "hero-chevron-up", else: "hero-chevron-down"
                      }
                      class="w-5 h-5 text-zinc-500"
                    />
                  </button>
                  <!-- Dropdown Panel -->
                  <div
                    :if={@guests_dropdown_open}
                    phx-click-away="close-guests-dropdown"
                    class="absolute z-10 w-full mt-1 bg-white border border-zinc-300 rounded-md shadow-lg p-4"
                  >
                    <div class="space-y-4">
                      <!-- Adults Counter -->
                      <div>
                        <label class="block text-sm font-semibold text-zinc-700 mb-2">
                          Number of Adults
                        </label>
                        <div class="flex items-center space-x-3">
                          <button
                            type="button"
                            phx-click="decrease-guests"
                            disabled={@guests_count <= 1}
                            class={[
                              "w-10 h-10 rounded-full border flex items-center justify-center transition-colors",
                              if(@guests_count <= 1,
                                do: "border-zinc-200 bg-zinc-100 text-zinc-400 cursor-not-allowed",
                                else: "border-zinc-300 hover:bg-zinc-50 text-zinc-700"
                              )
                            ]}
                          >
                            <.icon name="hero-minus" class="w-5 h-5" />
                          </button>
                          <span class="w-12 text-center font-medium text-lg text-zinc-900">
                            <%= @guests_count %>
                          </span>
                          <button
                            type="button"
                            phx-click="increase-guests"
                            class="w-10 h-10 rounded-full border-2 border-blue-700 bg-blue-700 hover:bg-blue-800 hover:border-blue-800 text-white flex items-center justify-center transition-all duration-200 font-semibold"
                          >
                            <.icon name="hero-plus" class="w-5 h-5" />
                          </button>
                        </div>
                      </div>
                      <!-- Children Counter -->
                      <div>
                        <label class="block text-sm font-semibold text-zinc-700 mb-2">
                          Number of Children (ages 5-17)
                        </label>
                        <div class="flex items-center space-x-3">
                          <button
                            type="button"
                            phx-click="decrease-children"
                            disabled={@children_count <= 0}
                            class={[
                              "w-10 h-10 rounded-full border flex items-center justify-center transition-colors",
                              if(@children_count <= 0,
                                do: "border-zinc-200 bg-zinc-100 text-zinc-400 cursor-not-allowed",
                                else: "border-zinc-300 hover:bg-zinc-50 text-zinc-700"
                              )
                            ]}
                          >
                            <.icon name="hero-minus" class="w-5 h-5" />
                          </button>
                          <span class="w-12 text-center font-medium text-lg text-zinc-900">
                            <%= @children_count %>
                          </span>
                          <button
                            type="button"
                            phx-click="increase-children"
                            class="w-10 h-10 rounded-full border-2 border-blue-700 bg-blue-700 hover:bg-blue-800 hover:border-blue-800 text-white flex items-center justify-center transition-all duration-200 font-semibold"
                          >
                            <.icon name="hero-plus" class="w-5 h-5" />
                          </button>
                        </div>
                      </div>
                      <p class="text-sm text-zinc-600 pt-2 border-t border-zinc-200">
                        Children 5-17 years: $25/night. Children under 5 stay for free.
                      </p>
                      <!-- Done Button -->
                      <div class="pt-2">
                        <button
                          type="button"
                          phx-click="close-guests-dropdown"
                          class="w-full px-4 py-2 bg-blue-700 hover:bg-blue-800 text-white font-semibold rounded-md transition-colors duration-200"
                        >
                          Done
                        </button>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
            <p :if={@form_errors[:checkin_date]} class="text-red-600 text-sm mt-1">
              <%= @form_errors[:checkin_date] %>
            </p>
            <p :if={@form_errors[:checkout_date]} class="text-red-600 text-sm mt-1">
              <%= @form_errors[:checkout_date] %>
            </p>
            <p :if={@date_validation_errors[:weekend]} class="text-red-600 text-sm mt-1">
              <%= @date_validation_errors[:weekend] %>
            </p>
            <p :if={@date_validation_errors[:max_nights]} class="text-red-600 text-sm mt-1">
              <%= @date_validation_errors[:max_nights] %>
            </p>
            <p :if={@date_validation_errors[:active_booking]} class="text-red-600 text-sm mt-1">
              <%= @date_validation_errors[:active_booking] %>
            </p>
            <p :if={@date_validation_errors[:advance_booking_limit]} class="text-red-600 text-sm mt-1">
              <%= @date_validation_errors[:advance_booking_limit] %>
            </p>
            <p :if={@date_validation_errors[:season_booking_mode]} class="text-red-600 text-sm mt-1">
              <%= @date_validation_errors[:season_booking_mode] %>
            </p>
          </div>
          <!-- Booking Mode Selection -->
          <div :if={@checkin_date}>
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
                <span>Individual Room(s)</span>
              </label>
              <label class={[
                "flex items-center",
                if(not can_select_booking_mode?(@checkin_date),
                  do: "opacity-50 cursor-not-allowed",
                  else: ""
                )
              ]}>
                <input
                  type="radio"
                  name="booking_mode"
                  value="buyout"
                  checked={@selected_booking_mode == :buyout}
                  disabled={not can_select_booking_mode?(@checkin_date)}
                  phx-change="booking-mode-changed"
                  class={[
                    "mr-2",
                    if(not can_select_booking_mode?(@checkin_date),
                      do: "cursor-not-allowed opacity-50",
                      else: ""
                    )
                  ]}
                  onclick={
                    if(not can_select_booking_mode?(@checkin_date), do: "return false;", else: "")
                  }
                />
                <span class={
                  if(not can_select_booking_mode?(@checkin_date), do: "text-zinc-400", else: "")
                }>
                  Full Buyout
                </span>
              </label>
            </div>
            <p
              :if={not can_select_booking_mode?(@checkin_date)}
              class="text-sm text-zinc-500 mt-2 ml-6"
            >
              Full buyout is only available during summer season.
            </p>
          </div>
          <!-- Room Selection (for room bookings) -->
          <div :if={@selected_booking_mode == :room && @checkin_date && @checkout_date}>
            <div class="mb-4 p-3 bg-zinc-50 border border-zinc-200 rounded-md">
              <div class="flex items-center justify-between">
                <div>
                  <p class="text-sm font-semibold text-zinc-900">Selected Dates</p>
                  <p class="text-sm text-zinc-600">
                    <%= Calendar.strftime(@checkin_date, "%B %d, %Y") %> - <%= Calendar.strftime(
                      @checkout_date,
                      "%B %d, %Y"
                    ) %>
                  </p>
                  <p class="text-xs text-zinc-500 mt-1">
                    <%= Date.diff(@checkout_date, @checkin_date) %> night(s)
                  </p>
                </div>
                <button
                  phx-click="clear-dates"
                  class="text-xs text-zinc-600 hover:text-zinc-900 underline"
                >
                  Change dates
                </button>
              </div>
            </div>
            <label class="block text-sm font-semibold text-zinc-700 mb-2">
              <%= if can_select_multiple_rooms?(assigns) do %>
                Select Room(s) <%= if length(@selected_room_ids) > 0,
                  do: "(#{length(@selected_room_ids)}/#{max_rooms_for_user(assigns)})",
                  else: "" %>
              <% else %>
                Select Room
              <% end %>
            </label>
            <div class="space-y-2">
              <%= for room <- @available_rooms do %>
                <% {availability, reason} = room.availability_status || {:available, nil} %>
                <% is_unavailable = availability == :unavailable %>
                <% max_rooms_reached =
                  can_select_multiple_rooms?(assigns) &&
                    length(@selected_room_ids) >= max_rooms_for_user(assigns) %>
                <% room_already_selected =
                  can_select_multiple_rooms?(assigns) && room.id in @selected_room_ids %>
                <% is_disabled = is_unavailable || (max_rooms_reached && !room_already_selected) %>
                <div class={[
                  "flex items-center p-3 border rounded-md",
                  if(is_disabled,
                    do: "border-zinc-200 bg-zinc-50 cursor-not-allowed opacity-60",
                    else: "border-zinc-300 hover:bg-zinc-50 cursor-pointer"
                  )
                ]}>
                  <label :if={!is_disabled} class="flex items-center flex-1 cursor-pointer">
                    <input
                      type={if can_select_multiple_rooms?(assigns), do: "checkbox", else: "radio"}
                      name={if can_select_multiple_rooms?(assigns), do: "room_ids", else: "room_id"}
                      value={room.id}
                      checked={
                        if can_select_multiple_rooms?(assigns) do
                          room.id in @selected_room_ids
                        else
                          @selected_room_id == room.id
                        end
                      }
                      phx-click="room-changed"
                      phx-value-room-id={room.id}
                      class="mr-3"
                    />
                    <div class="flex-1">
                      <div class="flex items-center justify-between">
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
                        <div class="ml-4 text-right">
                          <div :if={room.calculated_price} class="text-lg font-semibold text-blue-600">
                            <%= MoneyHelper.format_money!(room.calculated_price) %>
                          </div>
                          <div :if={!room.calculated_price} class="text-sm text-zinc-400">
                            Price unavailable
                          </div>
                        </div>
                      </div>
                    </div>
                  </label>
                  <div :if={is_disabled} class="flex items-center flex-1 cursor-not-allowed">
                    <input
                      type={if can_select_multiple_rooms?(assigns), do: "checkbox", else: "radio"}
                      name={if can_select_multiple_rooms?(assigns), do: "room_ids", else: "room_id"}
                      value={room.id}
                      checked={false}
                      disabled={true}
                      class="mr-3"
                      readonly
                    />
                    <div class="flex-1">
                      <div class="flex items-center justify-between">
                        <div class="flex-1">
                          <div class="font-medium text-zinc-400"><%= room.name %></div>
                          <div class="text-sm text-zinc-500">
                            <%= room.description %>
                            <span class="ml-2">• Max <%= room.capacity_max %> guests</span>
                            <span :if={room.min_billable_occupancy > 1} class="ml-2">
                              • Minimum <%= room.min_billable_occupancy %> guests
                            </span>
                          </div>
                          <div
                            :if={is_unavailable && reason}
                            class="text-sm text-amber-600 mt-1 font-medium"
                          >
                            ⚠️ <%= reason %>
                          </div>
                        </div>
                        <div class="ml-4 text-right">
                          <div :if={room.calculated_price} class="text-lg font-semibold text-zinc-400">
                            <%= MoneyHelper.format_money!(room.calculated_price) %>
                          </div>
                          <div :if={!room.calculated_price} class="text-sm text-zinc-400">
                            Price unavailable
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
            <p :if={@form_errors[:room_id]} class="text-red-600 text-sm mt-1">
              <%= @form_errors[:room_id] %>
            </p>
            <div
              :if={can_select_multiple_rooms?(assigns) && length(@selected_room_ids) > 0}
              class="mt-3 p-3 bg-blue-50 border border-blue-200 rounded-md"
            >
              <p class="text-sm font-semibold text-blue-900 mb-2">
                Selected Rooms (<%= length(@selected_room_ids) %>/<%= max_rooms_for_user(assigns) %>):
              </p>
              <ul class="text-sm text-blue-800 space-y-1">
                <%= for room_id <- @selected_room_ids do %>
                  <% room = Enum.find(@available_rooms, &(&1.id == room_id)) %>
                  <li :if={room} class="flex items-center justify-between">
                    <span>• <%= room.name %></span>
                    <button
                      phx-click="remove-room"
                      phx-value-room-id={room_id}
                      class="text-blue-600 hover:text-blue-800 text-xs underline"
                    >
                      Remove
                    </button>
                  </li>
                <% end %>
              </ul>
            </div>
            <p
              :if={
                can_select_multiple_rooms?(assigns) &&
                  length(@selected_room_ids) < max_rooms_for_user(assigns)
              }
              class="text-blue-600 text-sm mt-2"
            >
              💡 Family membership: You can book up to <%= max_rooms_for_user(assigns) %> rooms in the same reservation.
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
              <li>If booking contains Saturday, must also include Sunday (full weekend required)</li>
              <li>Only one active booking per user at a time (all seasons)</li>
              <li>Winter: Only individual rooms allowed</li>
              <li>Summer: Individual rooms or full buyout available</li>
              <li>Family/Lifetime membership: Can book up to 2 rooms in the same time period</li>
              <li>Single membership: Only 1 room per booking</li>
              <li>Reservations must adhere to accommodation limits for each room</li>
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
                  get_selected_rooms_for_submit(assigns)
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
        selected_room_ids: [],
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
        selected_room_ids: [],
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
        selected_room_ids: [],
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
    # Prevent switching to buyout during winter season
    if can_select_booking_mode?(socket.assigns.checkin_date) do
      socket =
        socket
        |> assign(
          selected_booking_mode: :buyout,
          selected_room_id: nil,
          selected_room_ids: [],
          available_rooms: [],
          calculated_price: nil,
          price_error: nil
        )
        |> calculate_price_if_ready()

      {:noreply, socket}
    else
      # Winter season: ignore buyout selection and keep room mode
      {:noreply, socket}
    end
  end

  def handle_event("room-changed", params, socket) do
    # Handle radio button or single checkbox toggle
    # Phoenix converts phx-value-room-id to "room-id" in params
    # Also handle nested value structure from checkbox events
    room_id_str =
      cond do
        Map.has_key?(params, "room_id") ->
          Map.get(params, "room_id")

        Map.has_key?(params, "room-id") ->
          Map.get(params, "room-id")

        Map.has_key?(params, "value") ->
          # Value might be a nested map or a string
          value = Map.get(params, "value")

          cond do
            is_map(value) -> Map.get(value, "room-id") || Map.get(value, "value")
            is_binary(value) -> value
            true -> nil
          end

        true ->
          nil
      end

    room_id = if room_id_str && room_id_str != "", do: room_id_str, else: nil

    # Check if room is available before allowing selection
    room = Enum.find(socket.assigns.available_rooms || [], &(&1.id == room_id))

    {availability, _reason} =
      if room,
        do: room.availability_status || {:available, nil},
        else: {:unavailable, "Room not found"}

    # Prevent selection of unavailable rooms
    if availability == :unavailable do
      {:noreply, socket}
    else
      # Determine if this is a checkbox toggle (family members) or radio selection
      if can_select_multiple_rooms?(socket.assigns) do
        # Checkbox: toggle the room in the selected list
        current_ids = socket.assigns.selected_room_ids || []
        room_id_to_toggle = room_id

        selected_room_ids =
          if room_id_to_toggle in current_ids do
            # Uncheck: remove from list
            List.delete(current_ids, room_id_to_toggle)
          else
            # Check: add to list (but respect max limit)
            max_rooms = max_rooms_for_user(socket.assigns)

            if length(current_ids) < max_rooms do
              [room_id_to_toggle | current_ids]
            else
              current_ids
            end
          end

        socket =
          socket
          |> assign(
            selected_room_ids: selected_room_ids,
            selected_room_id:
              if(length(selected_room_ids) == 1, do: List.first(selected_room_ids), else: nil),
            calculated_price: nil,
            price_error: nil
          )
          |> calculate_price_if_ready()

        {:noreply, socket}
      else
        # Radio button: single selection
        socket =
          socket
          |> assign(
            selected_room_id: room_id,
            selected_room_ids: if(room_id, do: [room_id], else: []),
            calculated_price: nil,
            price_error: nil
          )
          |> calculate_price_if_ready()

        {:noreply, socket}
      end
    end
  end

  def handle_event("remove-room", %{"room-id" => room_id}, socket) do
    # Remove room from selected list
    current_ids = socket.assigns.selected_room_ids || []
    selected_room_ids = List.delete(current_ids, room_id)

    socket =
      socket
      |> assign(
        selected_room_ids: selected_room_ids,
        selected_room_id:
          if(length(selected_room_ids) == 1, do: List.first(selected_room_ids), else: nil),
        calculated_price: nil,
        price_error: nil
      )
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  def handle_event("toggle-guests-dropdown", _params, socket) do
    {:noreply, assign(socket, guests_dropdown_open: !socket.assigns.guests_dropdown_open)}
  end

  def handle_event("close-guests-dropdown", _params, socket) do
    {:noreply, assign(socket, guests_dropdown_open: false)}
  end

  def handle_event("increase-guests", _params, socket) do
    new_count = (socket.assigns.guests_count || 1) + 1

    socket =
      socket
      |> assign(guests_count: new_count, calculated_price: nil, price_error: nil)
      |> update_url_with_search_params(
        socket.assigns.checkin_date,
        socket.assigns.checkout_date,
        new_count,
        socket.assigns.children_count
      )
      |> update_available_rooms()
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  def handle_event("decrease-guests", _params, socket) do
    current_count = socket.assigns.guests_count || 1
    new_count = max(1, current_count - 1)

    socket =
      socket
      |> assign(guests_count: new_count, calculated_price: nil, price_error: nil)
      |> update_url_with_search_params(
        socket.assigns.checkin_date,
        socket.assigns.checkout_date,
        new_count,
        socket.assigns.children_count
      )
      |> update_available_rooms()
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  def handle_event("increase-children", _params, socket) do
    new_count = (socket.assigns.children_count || 0) + 1

    socket =
      socket
      |> assign(children_count: new_count, calculated_price: nil, price_error: nil)
      |> update_url_with_search_params(
        socket.assigns.checkin_date,
        socket.assigns.checkout_date,
        socket.assigns.guests_count,
        new_count
      )
      |> update_available_rooms()
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  def handle_event("decrease-children", _params, socket) do
    current_count = socket.assigns.children_count || 0
    new_count = max(0, current_count - 1)

    socket =
      socket
      |> assign(children_count: new_count, calculated_price: nil, price_error: nil)
      |> update_url_with_search_params(
        socket.assigns.checkin_date,
        socket.assigns.checkout_date,
        socket.assigns.guests_count,
        new_count
      )
      |> update_available_rooms()
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  def handle_event("guests-changed", %{"guests_count" => guests_str}, socket) do
    guests_count = parse_integer(guests_str) || 1

    socket =
      socket
      |> assign(guests_count: guests_count, calculated_price: nil, price_error: nil)
      |> update_available_rooms()
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  def handle_event("children-changed", %{"children_count" => children_str}, socket) do
    children_count = parse_integer(children_str) || 0

    socket =
      socket
      |> assign(children_count: children_count, calculated_price: nil, price_error: nil)
      |> update_available_rooms()
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
      # Ensure valid guest/children counts for filtering
      # Get values from assigns with fallback, then parse to ensure valid integers
      raw_guests = Map.get(socket.assigns, :guests_count, 1)
      raw_children = Map.get(socket.assigns, :children_count, 0)

      # Parse and validate - these functions always return valid integers
      guests_count = parse_guests_count(raw_guests)
      children_count = parse_children_count(raw_children)

      # Final safety check - ensure we have valid integers before using
      guests_count =
        cond do
          is_integer(guests_count) && guests_count > 0 -> guests_count
          true -> 1
        end

      children_count =
        cond do
          is_integer(children_count) && children_count >= 0 -> children_count
          true -> 0
        end

      total_people = guests_count + children_count

      # Get ALL rooms for the property, not just available ones
      all_rooms = Bookings.list_rooms(socket.assigns.property)

      # Get available rooms for comparison
      available_room_ids =
        Bookings.get_available_rooms(
          socket.assigns.property,
          socket.assigns.checkin_date,
          socket.assigns.checkout_date
        )
        |> Enum.map(& &1.id)
        |> MapSet.new()

      # Check if user can select multiple rooms (family/lifetime members)
      can_select_multiple = can_select_multiple_rooms?(socket.assigns)

      rooms_with_status =
        all_rooms
        |> Enum.map(fn room ->
          # Determine availability status and reason
          is_available = MapSet.member?(available_room_ids, room.id)
          is_active = room.is_active

          # For users who can select multiple rooms, don't check capacity against total_people
          # because they can distribute guests across multiple rooms
          capacity_ok =
            if can_select_multiple do
              # If user can select multiple rooms, capacity is always OK (they can split guests)
              true
            else
              # Single room selection: capacity must accommodate all guests
              if total_people > 0, do: room.capacity_max >= total_people, else: true
            end

          availability_status =
            cond do
              not is_active ->
                {:unavailable, "Room is not active"}

              not is_available ->
                {:unavailable, "Already booked for selected dates"}

              not capacity_ok ->
                {:unavailable,
                 "Room capacity (#{room.capacity_max}) is less than number of guests (#{total_people})"}

              true ->
                {:available, nil}
            end

          Map.put(room, :availability_status, availability_status)
        end)
        |> Enum.map(fn room ->
          # Calculate price for each room
          # Ensure we have valid integers before calling calculate_booking_price
          # Use try-catch to handle any unexpected errors
          try do
            # Final validation - ensure we have proper integers
            final_guests =
              cond do
                is_integer(guests_count) && guests_count > 0 -> guests_count
                is_number(guests_count) && guests_count > 0 -> trunc(guests_count)
                true -> 1
              end

            final_children =
              cond do
                is_integer(children_count) && children_count >= 0 -> children_count
                is_number(children_count) && children_count >= 0 -> trunc(children_count)
                true -> 0
              end

            case Bookings.calculate_booking_price(
                   socket.assigns.property,
                   socket.assigns.checkin_date,
                   socket.assigns.checkout_date,
                   :room,
                   room.id,
                   final_guests,
                   final_children
                 ) do
              {:ok, price} -> Map.put(room, :calculated_price, price)
              {:error, _} -> Map.put(room, :calculated_price, nil)
            end
          rescue
            e ->
              # Log the error and return room without price
              Logger.error("Error calculating price for room #{room.id}: #{inspect(e)}")

              Logger.error(
                "guests_count: #{inspect(guests_count)}, children_count: #{inspect(children_count)}"
              )

              Map.put(room, :calculated_price, nil)
          end
        end)

      assign(socket, available_rooms: rooms_with_status)
    else
      assign(socket, available_rooms: [])
    end
  end

  defp calculate_price_if_ready(socket) do
    if ready_for_price_calculation?(socket) do
      # Ensure guests_count and children_count are valid integers
      guests_count = parse_guests_count(socket.assigns.guests_count)
      children_count = parse_children_count(socket.assigns.children_count)

      room_ids =
        if can_select_multiple_rooms?(socket.assigns) do
          socket.assigns.selected_room_ids
        else
          if socket.assigns.selected_room_id, do: [socket.assigns.selected_room_id], else: []
        end

      if socket.assigns.selected_booking_mode == :buyout do
        # Buyout pricing
        case Bookings.calculate_booking_price(
               socket.assigns.property,
               socket.assigns.checkin_date,
               socket.assigns.checkout_date,
               socket.assigns.selected_booking_mode,
               nil,
               guests_count,
               children_count
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
        # Calculate price for multiple rooms (sum them up)
        prices_result =
          Enum.reduce_while(room_ids, {:ok, Money.new(0, :USD)}, fn room_id, {:ok, total} ->
            if room_id && room_id != "" do
              # Use the parsed values from the outer scope
              case Bookings.calculate_booking_price(
                     socket.assigns.property,
                     socket.assigns.checkin_date,
                     socket.assigns.checkout_date,
                     :room,
                     room_id,
                     guests_count,
                     children_count
                   ) do
                {:ok, price} -> {:cont, {:ok, Money.add(total, price)}}
                {:error, reason} -> {:halt, {:error, reason}}
              end
            else
              {:halt, {:error, :invalid_room_id}}
            end
          end)

        case prices_result do
          {:ok, total_price} ->
            assign(socket, calculated_price: total_price, price_error: nil)

          {:error, reason} ->
            assign(socket,
              calculated_price: nil,
              price_error: "Unable to calculate price: #{inspect(reason)}"
            )
        end
      end
    else
      assign(socket, calculated_price: nil, price_error: nil)
    end
  end

  defp ready_for_price_calculation?(socket) do
    socket.assigns.checkin_date &&
      socket.assigns.checkout_date &&
      (socket.assigns.selected_booking_mode == :buyout ||
         (socket.assigns.selected_booking_mode == :room &&
            (socket.assigns.selected_room_id ||
               (can_select_multiple_rooms?(socket.assigns) &&
                  length(socket.assigns.selected_room_ids) > 0))))
  end

  defp can_select_booking_mode?(checkin_date) do
    if checkin_date do
      season = Season.for_date(:tahoe, checkin_date)
      season && season.name == "Summer"
    else
      false
    end
  end

  defp can_submit_booking?(booking_mode, checkin_date, checkout_date, room_ids_or_id) do
    has_rooms? =
      case room_ids_or_id do
        room_id when is_binary(room_id) -> not is_nil(room_id)
        room_ids when is_list(room_ids) -> length(room_ids) > 0
        _ -> false
      end

    checkin_date && checkout_date &&
      (booking_mode == :buyout || (booking_mode == :room && has_rooms?))
  end

  defp validate_and_create_booking(socket) do
    # Determine which rooms to book
    room_ids =
      if can_select_multiple_rooms?(socket.assigns) do
        socket.assigns.selected_room_ids
      else
        if socket.assigns.selected_room_id, do: [socket.assigns.selected_room_id], else: []
      end

    # If buyout, create single booking
    if socket.assigns.selected_booking_mode == :buyout do
      attrs = %{
        property: socket.assigns.property,
        checkin_date: socket.assigns.checkin_date,
        checkout_date: socket.assigns.checkout_date,
        booking_mode: socket.assigns.selected_booking_mode,
        room_id: nil,
        guests_count: socket.assigns.guests_count,
        children_count: socket.assigns.children_count,
        user_id: socket.assigns.user.id
      }

      changeset =
        Bookings.Booking.changeset(%Bookings.Booking{}, attrs, user: socket.assigns.user)

      case Ysc.Repo.insert(changeset) do
        {:ok, _booking} -> {:ok, :created}
        {:error, changeset} -> {:error, changeset}
      end
    else
      # Create multiple bookings atomically for multiple rooms
      create_multiple_bookings(socket, room_ids)
    end
  end

  defp create_multiple_bookings(socket, room_ids) do
    Repo.transaction(fn ->
      results =
        Enum.map(room_ids, fn room_id ->
          attrs = %{
            property: socket.assigns.property,
            checkin_date: socket.assigns.checkin_date,
            checkout_date: socket.assigns.checkout_date,
            booking_mode: :room,
            room_id: room_id,
            guests_count: socket.assigns.guests_count,
            children_count: socket.assigns.children_count,
            user_id: socket.assigns.user.id
          }

          changeset =
            Bookings.Booking.changeset(%Bookings.Booking{}, attrs, user: socket.assigns.user)

          case Repo.insert(changeset) do
            {:ok, booking} -> {:ok, booking}
            {:error, changeset} -> Repo.rollback({:error, changeset})
          end
        end)

      # If all succeeded, return success
      if Enum.all?(results, fn r -> match?({:ok, _}, r) end) do
        :ok
      else
        Repo.rollback({:error, "Failed to create all bookings"})
      end
    end)
    |> case do
      {:ok, :ok} -> {:ok, :created}
      {:error, changeset} -> {:error, changeset}
      {:error, reason} -> {:error, %Ecto.Changeset{errors: [general: reason]}}
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp date_to_datetime_string(nil), do: nil

  defp date_to_datetime_string(date) when is_struct(date, Date) do
    Date.to_string(date) <> "T00:00:00Z"
  end

  defp date_to_datetime_string(_), do: nil

  # URL parameter helpers

  # Parse query parameters, handling malformed/double-encoded URLs
  defp parse_query_params(params, uri) do
    # Priority 1: Use uri.query if available (most reliable)
    # Priority 2: Check for malformed key in params
    # Priority 3: Use params as-is

    cond do
      is_struct(uri, URI) && uri.query && uri.query != "" ->
        # uri.query is the most reliable source - it's the raw query string from the URL
        parsed = parse_query_string(uri.query)
        # Merge with existing params (path params take precedence)
        Map.merge(parsed, params)

      find_malformed_query_key(params) ->
        malformed_key = find_malformed_query_key(params)
        # Params are malformed - the entire query string is the key
        # Parse it directly from the key
        parsed = parse_query_string(malformed_key)
        # Remove the malformed key from params before merging
        clean_params = Map.delete(params, malformed_key)
        Map.merge(parsed, clean_params)

      true ->
        # Params are already correctly parsed
        params
    end
  end

  # Find a key that looks like a malformed query string (contains & and =)
  defp find_malformed_query_key(params) do
    Enum.find_value(params, fn
      {key, _value} when is_binary(key) ->
        if String.contains?(key, "&") and String.contains?(key, "=") do
          key
        else
          nil
        end

      _ ->
        nil
    end)
  end

  # Parse a query string into a map
  defp parse_query_string(query_string) when is_binary(query_string) do
    query_string
    |> String.split("&")
    |> Enum.reduce(%{}, fn pair, acc ->
      case String.split(pair, "=", parts: 2) do
        [key, value] ->
          decoded_key = URI.decode(key)
          decoded_value = URI.decode(value)
          Map.put(acc, decoded_key, decoded_value)

        [key] ->
          decoded_key = URI.decode(key)
          Map.put(acc, decoded_key, "")

        _ ->
          acc
      end
    end)
  end

  defp parse_query_string(_), do: %{}

  # Parse params in mount - handle malformed query strings
  defp parse_mount_params(params) when is_map(params) do
    # Check if params are malformed (single key with entire query string as key)
    case find_malformed_query_key(params) do
      nil ->
        # Params are already correctly parsed
        params

      malformed_key ->
        # Params are malformed - the entire query string is the key
        parsed = parse_query_string(malformed_key)
        # Remove the malformed key from params before merging
        clean_params = Map.delete(params, malformed_key)
        Map.merge(parsed, clean_params)
    end
  end

  defp parse_mount_params(_), do: %{}

  defp parse_dates_from_params(params) do
    checkin_date =
      case params["checkin_date"] || params[:checkin_date] do
        nil ->
          nil

        date_str when is_binary(date_str) ->
          case Date.from_iso8601(date_str) do
            {:ok, date} -> date
            _ -> nil
          end

        _ ->
          nil
      end

    checkout_date =
      case params["checkout_date"] || params[:checkout_date] do
        nil ->
          nil

        date_str when is_binary(date_str) ->
          case Date.from_iso8601(date_str) do
            {:ok, date} -> date
            _ -> nil
          end

        _ ->
          nil
      end

    {checkin_date, checkout_date}
  end

  defp parse_guests_from_params(params) do
    case Map.get(params, "guests_count") do
      nil ->
        1

      guests_str when is_binary(guests_str) ->
        case Integer.parse(guests_str) do
          {parsed, _} when parsed > 0 -> parsed
          _ -> 1
        end

      guests when is_integer(guests) and guests > 0 ->
        guests

      _ ->
        1
    end
  end

  defp parse_children_from_params(params) do
    case Map.get(params, "children_count") do
      nil ->
        0

      children_str when is_binary(children_str) ->
        case Integer.parse(children_str) do
          {parsed, _} when parsed >= 0 -> parsed
          _ -> 0
        end

      children when is_integer(children) and children >= 0 ->
        children

      _ ->
        0
    end
  end

  defp update_url_with_dates(socket, checkin_date, checkout_date) do
    guests_count = socket.assigns.guests_count || 1
    children_count = socket.assigns.children_count || 0
    query_params = build_query_params(checkin_date, checkout_date, guests_count, children_count)

    if map_size(query_params) > 0 do
      push_patch(socket, to: ~p"/bookings/tahoe?#{URI.encode_query(query_params)}")
    else
      push_patch(socket, to: ~p"/bookings/tahoe")
    end
  end

  defp update_url_with_search_params(
         socket,
         checkin_date,
         checkout_date,
         guests_count,
         children_count
       ) do
    query_params = build_query_params(checkin_date, checkout_date, guests_count, children_count)

    if map_size(query_params) > 0 do
      push_patch(socket, to: ~p"/bookings/tahoe?#{URI.encode_query(query_params)}")
    else
      push_patch(socket, to: ~p"/bookings/tahoe")
    end
  end

  defp build_query_params(checkin_date, checkout_date, guests_count \\ 1, children_count \\ 0) do
    params = %{}

    params =
      if checkin_date do
        Map.put(params, "checkin_date", Date.to_string(checkin_date))
      else
        params
      end

    params =
      if checkout_date do
        Map.put(params, "checkout_date", Date.to_string(checkout_date))
      else
        params
      end

    params =
      if guests_count && guests_count > 0 do
        Map.put(params, "guests_count", Integer.to_string(guests_count))
      else
        params
      end

    params =
      if children_count && children_count > 0 do
        Map.put(params, "children_count", Integer.to_string(children_count))
      else
        params
      end

    params
  end

  # Real-time validation functions

  # Enforces season rules: Winter = room only, Summer = room or buyout
  defp enforce_season_booking_mode(socket) do
    if socket.assigns.checkin_date do
      season = Season.for_date(:tahoe, socket.assigns.checkin_date)

      if season && season.name == "Winter" && socket.assigns.selected_booking_mode == :buyout do
        # Winter season: force booking mode to room
        socket
        |> assign(
          selected_booking_mode: :room,
          selected_room_id: nil,
          selected_room_ids: [],
          calculated_price: nil,
          price_error: nil
        )
      else
        socket
      end
    else
      socket
    end
  end

  defp validate_dates(socket) do
    errors = %{}

    errors =
      if socket.assigns.checkin_date && socket.assigns.checkout_date do
        errors
        |> validate_advance_booking_limit(
          socket.assigns.checkin_date,
          socket.assigns.checkout_date
        )
        |> validate_weekend_rule(socket.assigns.checkin_date, socket.assigns.checkout_date)
        |> validate_max_nights(socket.assigns.checkin_date, socket.assigns.checkout_date)
        |> validate_season_booking_mode(socket)
      else
        errors
      end

    errors =
      validate_active_booking(%{
        socket
        | assigns: Map.put(socket.assigns, :date_validation_errors, errors)
      })

    assign(socket, date_validation_errors: errors)
  end

  defp validate_advance_booking_limit(errors, checkin_date, checkout_date) do
    today = Date.utc_today()
    max_booking_date = Date.add(today, 45)

    # Check if check-in date is more than 45 days out
    if Date.compare(checkin_date, max_booking_date) == :gt do
      Map.put(
        errors,
        :advance_booking_limit,
        "Bookings can only be made up to 45 days in advance. Maximum check-in date is #{Calendar.strftime(max_booking_date, "%B %d, %Y")}"
      )
    else
      # Also check checkout date in case it extends beyond the limit
      if Date.compare(checkout_date, max_booking_date) == :gt do
        Map.put(
          errors,
          :advance_booking_limit,
          "Bookings can only be made up to 45 days in advance. Maximum check-out date is #{Calendar.strftime(max_booking_date, "%B %d, %Y")}"
        )
      else
        errors
      end
    end
  end

  defp validate_season_booking_mode(errors, socket) do
    if socket.assigns.checkin_date && socket.assigns.selected_booking_mode do
      season = Season.for_date(:tahoe, socket.assigns.checkin_date)

      if season && season.name == "Winter" && socket.assigns.selected_booking_mode == :buyout do
        Map.put(
          errors,
          :season_booking_mode,
          "Winter season only allows individual room bookings, not buyouts"
        )
      else
        errors
      end
    else
      errors
    end
  end

  defp validate_weekend_rule(errors, checkin_date, checkout_date) do
    date_range = Date.range(checkin_date, checkout_date) |> Enum.to_list()

    has_saturday =
      Enum.any?(date_range, fn date ->
        Date.day_of_week(date) == 6
      end)

    if has_saturday do
      has_sunday =
        Enum.any?(date_range, fn date ->
          Date.day_of_week(date) == 7
        end)

      if not has_sunday do
        Map.put(
          errors,
          :weekend,
          "Bookings containing Saturday must also include Sunday (full weekend required)"
        )
      else
        errors
      end
    else
      errors
    end
  end

  defp validate_max_nights(errors, checkin_date, checkout_date) do
    nights = Date.diff(checkout_date, checkin_date)

    if nights > 4 do
      Map.put(errors, :max_nights, "Maximum 4 nights allowed per booking")
    else
      errors
    end
  end

  defp validate_active_booking(socket) do
    errors = socket.assigns.date_validation_errors || %{}

    if socket.assigns.checkin_date && socket.assigns.checkout_date && socket.assigns.user do
      user_id = socket.assigns.user.id

      overlapping_query =
        from b in Booking,
          where: b.user_id == ^user_id,
          where: b.property == :tahoe,
          where:
            fragment(
              "? < ? AND ? > ?",
              b.checkin_date,
              ^socket.assigns.checkout_date,
              b.checkout_date,
              ^socket.assigns.checkin_date
            )

      if Repo.exists?(overlapping_query) do
        Map.put(
          errors,
          :active_booking,
          "You can only have one active booking at a time. Please complete your existing booking first."
        )
      else
        errors
      end
    else
      errors
    end
  end

  defp get_membership_type(user) do
    if Ysc.Accounts.has_lifetime_membership?(user) do
      :lifetime
    else
      subscriptions =
        case user.subscriptions do
          %Ecto.Association.NotLoaded{} ->
            Subscriptions.list_subscriptions(user)

          subscriptions when is_list(subscriptions) ->
            subscriptions

          _ ->
            []
        end

      active_subscriptions =
        Enum.filter(subscriptions, fn sub ->
          Subscriptions.valid?(sub)
        end)

      case active_subscriptions do
        [] ->
          :none

        [subscription | _] ->
          get_membership_type_from_subscription(subscription)

        multiple ->
          most_expensive = get_most_expensive_subscription(multiple)
          get_membership_type_from_subscription(most_expensive)
      end
    end
  end

  defp get_membership_type_from_subscription(subscription) do
    # Only preload if not already loaded
    subscription =
      case subscription.subscription_items do
        %Ecto.Association.NotLoaded{} ->
          Ysc.Repo.preload(subscription, :subscription_items)

        _ ->
          subscription
      end

    case subscription.subscription_items do
      [item | _] ->
        membership_plans = Application.get_env(:ysc, :membership_plans, [])

        case Enum.find(membership_plans, &(&1.stripe_price_id == item.stripe_price_id)) do
          %{id: id} -> id
          _ -> :none
        end

      _ ->
        :none
    end
  end

  defp get_most_expensive_subscription(subscriptions) do
    membership_plans = Application.get_env(:ysc, :membership_plans, [])

    price_to_amount =
      Map.new(membership_plans, fn plan ->
        {plan.stripe_price_id, plan.amount}
      end)

    Enum.max_by(subscriptions, fn subscription ->
      case subscription.subscription_items do
        [item | _] ->
          Map.get(price_to_amount, item.stripe_price_id, 0)

        _ ->
          0
      end
    end)
  end

  defp can_add_second_room?(assigns) do
    if assigns.checkin_date && assigns.checkout_date && assigns.user do
      membership_type = get_membership_type(assigns.user)

      if membership_type in [:family, :lifetime] do
        user_id = assigns.user.id

        overlapping_query =
          from b in Booking,
            where: b.user_id == ^user_id,
            where: b.property == :tahoe,
            where: not is_nil(b.room_id),
            where:
              fragment(
                "? < ? AND ? > ?",
                b.checkin_date,
                ^assigns.checkout_date,
                b.checkout_date,
                ^assigns.checkin_date
              )

        existing_count = Repo.aggregate(overlapping_query, :count, :id)
        existing_count < 2
      else
        false
      end
    else
      false
    end
  end

  defp can_select_multiple_rooms?(assigns) do
    # Use cached membership_type if available, otherwise compute it
    membership_type =
      case assigns[:membership_type] do
        nil ->
          if assigns.user do
            get_membership_type(assigns.user)
          else
            :none
          end

        type ->
          type
      end

    membership_type in [:family, :lifetime]
  end

  defp max_rooms_for_user(user_or_assigns) do
    # Handle both user struct and assigns map
    membership_type =
      cond do
        is_map(user_or_assigns) && Map.has_key?(user_or_assigns, :membership_type) ->
          user_or_assigns.membership_type

        is_map(user_or_assigns) && Map.has_key?(user_or_assigns, :user) ->
          # It's an assigns map with user
          case user_or_assigns[:membership_type] do
            nil -> get_membership_type(user_or_assigns.user)
            type -> type
          end

        true ->
          # It's a user struct
          get_membership_type(user_or_assigns)
      end

    case membership_type do
      :family -> 2
      :lifetime -> 2
      _ -> 1
    end
  end

  defp has_room_selected?(assigns) do
    if can_select_multiple_rooms?(assigns) do
      length(assigns.selected_room_ids) > 0
    else
      not is_nil(assigns.selected_room_id)
    end
  end

  defp get_selected_rooms_for_submit(assigns) do
    if can_select_multiple_rooms?(assigns) do
      assigns.selected_room_ids
    else
      assigns.selected_room_id
    end
  end

  defp parse_guests_count(count) do
    case count do
      count when is_integer(count) and count > 0 ->
        count

      count when is_binary(count) ->
        case Integer.parse(count) do
          {parsed, _} when parsed > 0 -> parsed
          _ -> 1
        end

      _ ->
        1
    end
  end

  defp parse_children_count(count) do
    case count do
      count when is_integer(count) and count >= 0 ->
        count

      count when is_binary(count) ->
        case Integer.parse(count) do
          {parsed, _} when parsed >= 0 -> parsed
          _ -> 0
        end

      _ ->
        0
    end
  end

  defp format_guests_display(guests_count, children_count) do
    guests_text = if guests_count == 1, do: "1 adult", else: "#{guests_count} adults"

    children_text =
      cond do
        children_count == 0 -> nil
        children_count == 1 -> "1 child"
        true -> "#{children_count} children"
      end

    if children_text do
      "#{guests_text} • #{children_text}"
    else
      guests_text
    end
  end

  defp calculate_max_guests(assigns) do
    if can_select_multiple_rooms?(assigns) && length(assigns.selected_room_ids) > 0 do
      # For multiple rooms, sum the max capacity
      assigns.selected_room_ids
      |> Enum.map(fn room_id ->
        room = Enum.find(assigns.available_rooms, &(&1.id == room_id))
        if room, do: room.capacity_max, else: 0
      end)
      |> Enum.sum()
      |> max(1)
    else
      if assigns.selected_room_id do
        room = Enum.find(assigns.available_rooms, &(&1.id == assigns.selected_room_id))
        if room, do: room.capacity_max, else: 1
      else
        1
      end
    end
  end
end
