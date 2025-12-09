defmodule YscWeb.ClearLakeBookingLive do
  use YscWeb, :live_view

  alias Ysc.Bookings
  alias Ysc.Bookings.{Booking, SeasonHelpers, PricingHelpers, BookingLocker}
  alias Ysc.MoneyHelper
  alias Ysc.Accounts
  alias Ysc.Subscriptions
  alias Ysc.Repo
  import Ecto.Query

  @max_guests 12

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user

    today = Date.utc_today()

    {current_season, season_start_date, season_end_date} =
      SeasonHelpers.get_current_season_info(:clear_lake, today)

    max_booking_date = SeasonHelpers.calculate_max_booking_date(:clear_lake, today)

    # Parse query parameters, handling malformed/double-encoded URLs
    parsed_params = parse_mount_params(params)

    # Parse dates and guest counts from URL params if present
    {checkin_date, checkout_date} = parse_dates_from_params(parsed_params)
    guests_count = parse_guests_from_params(parsed_params)
    requested_tab = parse_tab_from_params(parsed_params)
    booking_mode = parse_booking_mode_from_params(parsed_params)

    date_form =
      to_form(
        %{
          "checkin_date" => date_to_datetime_string(checkin_date),
          "checkout_date" => date_to_datetime_string(checkout_date)
        },
        as: "booking_dates"
      )

    # Check if user can book
    {can_book, booking_disabled_reason} = check_booking_eligibility(user)

    # If user can't book, default to information tab
    active_tab =
      if !can_book do
        :information
      else
        requested_tab
      end

    # Use preloaded subscriptions from auth if available, otherwise load them
    user_with_subs =
      if user do
        # Check if subscriptions are already preloaded from auth
        if Ecto.assoc_loaded?(user.subscriptions) do
          user
        else
          # Only load if not already preloaded
          Accounts.get_user!(user.id)
          |> Ysc.Repo.preload(:subscriptions)
        end
      else
        nil
      end

    # Calculate membership type once and cache it (if user exists)
    membership_type =
      if user_with_subs do
        get_membership_type(user_with_subs)
      else
        :none
      end

    # Check which booking modes are allowed based on selected dates
    {day_booking_allowed, buyout_booking_allowed} =
      allowed_booking_modes(:clear_lake, checkin_date, checkout_date, current_season)

    # Resolve booking mode based on allowed modes (handles defaults and invalid selections)
    booking_mode = resolve_booking_mode(booking_mode, day_booking_allowed, buyout_booking_allowed)

    # Load active bookings for the user
    active_bookings = if user_with_subs, do: get_active_bookings(user_with_subs.id), else: []

    socket =
      assign(socket,
        page_title: "Clear Lake Cabin",
        property: :clear_lake,
        user: user_with_subs,
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        today: today,
        max_booking_date: max_booking_date,
        current_season: current_season,
        season_start_date: season_start_date,
        season_end_date: season_end_date,
        selected_booking_mode: booking_mode,
        guests_count: guests_count,
        max_guests: @max_guests,
        calculated_price: nil,
        price_error: nil,
        availability_error: nil,
        form_errors: %{},
        date_validation_errors: %{},
        date_form: date_form,
        membership_type: membership_type,
        active_tab: active_tab,
        can_book: can_book,
        booking_disabled_reason: booking_disabled_reason,
        day_booking_allowed: day_booking_allowed,
        buyout_booking_allowed: buyout_booking_allowed,
        active_bookings: active_bookings,
        load_radar: true
      )

    # Validate all conditions (availability, booking mode, guests, etc.)
    socket =
      socket
      |> validate_all_conditions(
        checkin_date,
        checkout_date,
        booking_mode,
        guests_count,
        current_season
      )
      |> then(fn s ->
        # If dates are present and user can book, initialize price calculation
        if checkin_date && checkout_date && can_book do
          s
          |> calculate_price_if_ready()
        else
          s
        end
      end)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, uri, socket) do
    # Parse query parameters, handling malformed/double-encoded URLs
    params = parse_query_params(params, uri)

    # Parse dates and guest counts from URL params
    {checkin_date, checkout_date} = parse_dates_from_params(params)
    guests_count = parse_guests_from_params(params)
    requested_tab = parse_tab_from_params(params)
    booking_mode = parse_booking_mode_from_params(params)

    # Check if user can book (re-check in case user state changed)
    user = socket.assigns.current_user
    {can_book, booking_disabled_reason} = check_booking_eligibility(user)

    # Load active bookings for the user (only if not already loaded in mount)
    active_bookings =
      if user && !socket.assigns[:active_bookings] do
        get_active_bookings(user.id)
      else
        socket.assigns[:active_bookings] || []
      end

    # If user can't book and requested booking tab, switch to information tab
    active_tab =
      if requested_tab == :booking && !can_book do
        :information
      else
        requested_tab
      end

    # Check if tab changed (but nothing else)
    tab_changed = active_tab != socket.assigns.active_tab

    # Update if dates, guest counts, or tab have changed
    # Use Date.compare for proper date comparison
    dates_changed =
      case {checkin_date, socket.assigns.checkin_date} do
        {nil, nil} -> false
        {nil, _} -> true
        {_, nil} -> true
        {c1, c2} -> Date.compare(c1, c2) != :eq
      end ||
        case {checkout_date, socket.assigns.checkout_date} do
          {nil, nil} -> false
          {nil, _} -> true
          {_, nil} -> true
          {c1, c2} -> Date.compare(c1, c2) != :eq
        end

    guests_changed = guests_count != socket.assigns.guests_count
    booking_mode_changed = booking_mode != socket.assigns.selected_booking_mode

    # Also check if can_book or booking_disabled_reason changed
    can_book_changed =
      can_book != socket.assigns.can_book ||
        booking_disabled_reason != socket.assigns.booking_disabled_reason

    # Only update if something actually changed
    # This prevents unnecessary updates on initial page load when mount already set everything
    if dates_changed || guests_changed || tab_changed || booking_mode_changed || can_book_changed do
      # Only recalculate today and max_booking_date if dates changed
      # This prevents unnecessary component updates
      {today, max_booking_date, current_season, season_start_date, season_end_date} =
        if dates_changed do
          today = Date.utc_today()

          {current_season, season_start_date, season_end_date} =
            SeasonHelpers.get_current_season_info(:clear_lake, today)

          max_booking_date = SeasonHelpers.calculate_max_booking_date(:clear_lake, today)

          {today, max_booking_date, current_season, season_start_date, season_end_date}
        else
          {
            socket.assigns.today,
            socket.assigns.max_booking_date,
            socket.assigns.current_season,
            socket.assigns.season_start_date,
            socket.assigns.season_end_date
          }
        end

      date_form =
        to_form(
          %{
            "checkin_date" => date_to_datetime_string(checkin_date),
            "checkout_date" => date_to_datetime_string(checkout_date)
          },
          as: "booking_dates"
        )

      # Check which booking modes are allowed based on selected dates
      {day_booking_allowed, buyout_booking_allowed} =
        allowed_booking_modes(:clear_lake, checkin_date, checkout_date, current_season)

      # Resolve booking mode based on allowed modes
      # This ensures we default to a valid mode if the requested one is not allowed
      # or if no mode was requested (booking_mode is nil)
      resolved_booking_mode =
        resolve_booking_mode(booking_mode, day_booking_allowed, buyout_booking_allowed)

      # Validate all conditions (availability, booking mode, guests, etc.)
      # This ensures URL parameters are validated even if user manipulates them
      socket =
        socket
        |> assign(
          page_title: "Clear Lake Cabin",
          checkin_date: checkin_date,
          checkout_date: checkout_date,
          today: today,
          max_booking_date: max_booking_date,
          current_season: current_season,
          season_start_date: season_start_date,
          season_end_date: season_end_date,
          guests_count: guests_count,
          selected_booking_mode: resolved_booking_mode,
          calculated_price: nil,
          price_error: nil,
          availability_error: nil,
          form_errors: %{},
          date_form: date_form,
          date_validation_errors: %{},
          active_tab: active_tab,
          can_book: can_book,
          booking_disabled_reason: booking_disabled_reason,
          day_booking_allowed: day_booking_allowed,
          buyout_booking_allowed: buyout_booking_allowed,
          active_bookings: active_bookings
        )
        |> validate_all_conditions(
          checkin_date,
          checkout_date,
          resolved_booking_mode,
          guests_count,
          current_season
        )
        |> then(fn s ->
          # Update date form with validated/corrected dates
          validated_date_form =
            to_form(
              %{
                "checkin_date" => date_to_datetime_string(s.assigns.checkin_date),
                "checkout_date" => date_to_datetime_string(s.assigns.checkout_date)
              },
              as: "booking_dates"
            )

          s
          |> assign(:date_form, validated_date_form)
          |> then(fn updated_s ->
            # Only run price calculation if dates, guests, or booking mode changed, not just tab
            if dates_changed || guests_changed || booking_mode_changed do
              updated_s
              |> calculate_price_if_ready()
            else
              updated_s
            end
          end)
        end)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="py-8 lg:py-10">
      <div class="max-w-screen-xl mx-auto flex flex-col px-4 space-y-6 lg:px-10">
        <div class="prose prose-zinc">
          <h1>Clear Lake Cabin</h1>
          <p>
            Select your dates and number of guests to make a reservation at our Clear Lake cabin.
          </p>
        </div>
        <!-- Active Bookings List -->
        <div :if={@user && length(@active_bookings) > 0} class="mb-6">
          <div class="flex items-start">
            <div class="flex-1">
              <h3 class="text-lg font-semibold text-zinc-900 mb-3">Your Active Bookings</h3>
              <div class="space-y-3">
                <%= for booking <- @active_bookings do %>
                  <div class="bg-white rounded-md p-3 border border-zinc-200">
                    <div class="flex items-start justify-between">
                      <div class="flex-1">
                        <div class="flex items-center gap-2 mb-1 pb-1">
                          <.link
                            navigate={~p"/bookings/#{booking.id}"}
                            class="hover:text-blue-600 transition-colors"
                          >
                            <.badge>
                              <%= booking.reference_id %>
                            </.badge>
                          </.link>
                          <span class="text-sm text-zinc-600 font-medium">
                            <%= if booking.booking_mode == :buyout do
                              "Full Buyout"
                            else
                              "A La Carte"
                            end %>
                          </span>
                        </div>
                        <div class="text-sm text-zinc-600">
                          <div class="flex items-center gap-4">
                            <span>
                              <span class="font-medium">Check-in:</span> <%= Calendar.strftime(
                                booking.checkin_date,
                                "%B %d, %Y"
                              ) %>
                            </span>
                            <span>
                              <span class="font-medium">Check-out:</span> <%= Calendar.strftime(
                                booking.checkout_date,
                                "%B %d, %Y"
                              ) %>
                            </span>
                          </div>
                          <div class="mt-1">
                            <%= booking.guests_count %> <%= if booking.guests_count == 1,
                              do: "guest",
                              else: "guests" %>
                          </div>
                        </div>
                      </div>
                      <div class="ml-4 flex flex-col items-end gap-2">
                        <span
                          :if={Date.compare(booking.checkin_date, @today) == :eq}
                          class="text-xs font-semibold text-blue-600 bg-blue-100 px-2 py-1 rounded"
                        >
                          Today
                        </span>
                        <span
                          :if={Date.compare(booking.checkin_date, @today) == :gt}
                          class="text-xs text-zinc-500"
                        >
                          <%= Date.diff(booking.checkin_date, @today) %> <%= if Date.diff(
                                                                                  booking.checkin_date,
                                                                                  @today
                                                                                ) == 1,
                                                                                do: "day",
                                                                                else: "days" %> until check-in
                        </span>
                        <.link
                          navigate={~p"/bookings/#{booking.id}"}
                          class="text-blue-600 hover:text-blue-800 text-xs font-medium"
                        >
                          View Details →
                        </.link>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
        <!-- Booking Eligibility Banner -->
        <div :if={!@can_book} class="bg-amber-50 border border-amber-200 rounded-lg p-4">
          <div class="flex items-start">
            <div class="flex-shrink-0">
              <.icon name="hero-exclamation-triangle-solid" class="h-5 w-5 text-amber-600" />
            </div>
            <div class="ms-2 flex-1">
              <h3 class="text-sm font-semibold text-amber-900">Booking Not Available</h3>
              <div class="mt-2 text-sm text-amber-800">
                <p><%= raw(@booking_disabled_reason) %></p>
              </div>
            </div>
          </div>
        </div>
        <!-- Tabs Navigation -->
        <div class="border-b border-zinc-200">
          <nav class="-mb-px flex space-x-8" aria-label="Tabs">
            <button
              phx-click="switch-tab"
              phx-value-tab="booking"
              disabled={!@can_book}
              class={[
                "whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm transition-colors",
                if(!@can_book,
                  do: "border-transparent text-zinc-400 cursor-not-allowed opacity-50",
                  else:
                    if(@active_tab == :booking,
                      do: "border-blue-500 text-blue-600",
                      else:
                        "border-transparent text-zinc-500 hover:text-zinc-700 hover:border-zinc-300"
                    )
                )
              ]}
            >
              Make a Reservation
            </button>
            <button
              phx-click="switch-tab"
              phx-value-tab="information"
              class={[
                "whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm transition-colors",
                if(@active_tab == :information,
                  do: "border-blue-500 text-blue-600",
                  else: "border-transparent text-zinc-500 hover:text-zinc-700 hover:border-zinc-300"
                )
              ]}
            >
              Cabin Information & Rules
            </button>
          </nav>
        </div>
        <!-- Booking Tab Content -->
        <div
          :if={@active_tab == :booking}
          class={[
            "bg-white rounded-lg border border-zinc-200 p-6 space-y-6",
            if(!@can_book, do: "relative opacity-60", else: "")
          ]}
        >
          <div
            :if={!@can_book}
            class="absolute inset-0 bg-white bg-opacity-50 rounded-lg pointer-events-none z-10"
          >
          </div>
          <!-- Booking Mode Selection -->
          <div>
            <fieldset>
              <legend class="block text-lg font-semibold text-zinc-700 mb-2">
                Booking Type
              </legend>
              <form phx-change="booking-mode-changed">
                <div class="flex gap-4" role="radiogroup">
                  <label class={[
                    "flex items-center",
                    if(!@day_booking_allowed, do: "opacity-50 cursor-not-allowed", else: "")
                  ]}>
                    <input
                      type="radio"
                      id="booking-mode-day"
                      name="booking_mode"
                      value="day"
                      checked={@selected_booking_mode == :day}
                      disabled={!@day_booking_allowed}
                      class="mr-2"
                    />
                    <span>A La Carte (Shared Stay)</span>
                  </label>
                  <label class={[
                    "flex items-center",
                    if(!@buyout_booking_allowed, do: "opacity-50 cursor-not-allowed", else: "")
                  ]}>
                    <input
                      type="radio"
                      id="booking-mode-buyout"
                      name="booking_mode"
                      value="buyout"
                      checked={@selected_booking_mode == :buyout}
                      disabled={!@buyout_booking_allowed}
                      class="mr-2"
                    />
                    <span>Full Buyout (Exclusive Rental)</span>
                  </label>
                </div>
              </form>
            </fieldset>
            <div class="mt-3">
              <p class="text-sm text-zinc-600">
                <span :if={@selected_booking_mode == :day && @day_booking_allowed}>
                  <strong>A La Carte (Shared Stay)</strong>
                  — Book individual spots for up to 12 guests per day. You'll share the cabin with other guests. Perfect for smaller groups!
                </span>
                <span :if={@selected_booking_mode == :buyout && @buyout_booking_allowed}>
                  <strong>Full Buyout (Exclusive Rental)</strong>
                  — Reserve the entire cabin exclusively for your group. You'll have the entire cabin to yourself. Perfect for larger groups or special occasions!
                </span>
                <span
                  :if={
                    !@day_booking_allowed && !@buyout_booking_allowed &&
                      (@checkin_date || @checkout_date)
                  }
                  class="text-amber-600 font-medium"
                >
                  Please select dates to see available booking options for your selected period.
                </span>
                <span
                  :if={!@day_booking_allowed && @selected_booking_mode == :day && @checkin_date}
                  class="text-amber-600 font-medium"
                >
                  A La Carte bookings are not available for the selected dates based on season settings.
                </span>
                <span
                  :if={!@buyout_booking_allowed && @selected_booking_mode == :buyout && @checkin_date}
                  class="text-amber-600 font-medium"
                >
                  Full Buyout bookings are not available for the selected dates based on season settings.
                </span>
              </p>
            </div>
          </div>
          <!-- Availability Calendar -->
          <div class="space-y-4">
            <div>
              <div class="block font-semibold text-lg text-zinc-700 mb-2">
                Select Dates
              </div>
              <div class="mb-4">
                <p class="text-sm font-medium text-zinc-800 mb-2">
                  <span :if={@selected_booking_mode == :day}>
                    Select your dates — The calendar shows how many spots are available for each day (up to 12 guests per day).
                  </span>
                  <span :if={@selected_booking_mode == :buyout}>
                    Select your dates — The calendar shows which dates are available for exclusive full cabin rental.
                  </span>
                </p>
                <p class="text-xs text-zinc-600">
                  Click on a date to start your selection, then click another date to complete your range.
                </p>
              </div>
              <.live_component
                module={YscWeb.Components.AvailabilityCalendar}
                id="clear-lake-availability-calendar"
                checkin_date={@checkin_date}
                checkout_date={@checkout_date}
                selected_booking_mode={@selected_booking_mode}
                min={@today}
                max={@max_booking_date}
                property={:clear_lake}
                today={@today}
                guests_count={@guests_count}
              />
              <div :if={@checkin_date || @checkout_date} class="mt-4 flex justify-end">
                <button
                  type="button"
                  phx-click="reset-dates"
                  class="inline-flex items-center px-4 py-2 text-sm font-medium text-zinc-700 bg-white border border-zinc-300 rounded-md hover:bg-zinc-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 transition-colors"
                >
                  <svg
                    class="w-4 h-4 mr-1"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                  >
                    <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                  Reset Dates
                </button>
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
            <p :if={@date_validation_errors[:season_date_range]} class="text-red-600 text-sm mt-1">
              <%= @date_validation_errors[:season_date_range] %>
            </p>
          </div>
          <!-- Guests Count (for day bookings) -->
          <div
            :if={@selected_booking_mode == :day}
            class="bg-blue-50 border-2 border-blue-300 rounded-lg p-4"
          >
            <label for="guests_count" class="block text-sm font-bold text-blue-900 mb-2">
              Number of Guests (A La Carte Booking)
            </label>
            <p class="text-xs text-blue-700 mb-3">
              Select how many guests will be staying. The calendar shows available spots for each day (up to 12 guests per day).
            </p>
            <form phx-change="guests-changed" phx-debounce="300">
              <input
                type="number"
                name="guests_count"
                id="guests_count"
                min="1"
                max={@max_guests || 12}
                step="1"
                value={@guests_count}
                oninput={"const max = #{@max_guests || 12}; if (this.value !== '') { const val = parseInt(this.value); if (!isNaN(val)) { this.value = Math.max(1, Math.min(max, val)); } }"}
                onblur={"const max = #{@max_guests || 12}; const val = parseInt(this.value); if (isNaN(val) || val < 1) { this.value = 1; } else if (val > max) { this.value = max; }"}
                class="w-full px-3 py-2 border-2 border-blue-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500 bg-white"
              />
            </form>
            <p class="text-sm text-blue-800 mt-2 font-medium">
              Maximum <%= @max_guests %> guests per day
            </p>
            <p class="text-xs text-blue-700 mt-1 italic">
              Note: Children up to and including 5 years old can join for free. Please do not include them when registering attendees.
            </p>
            <p :if={@form_errors[:guests_count]} class="text-red-600 text-sm mt-1">
              <%= @form_errors[:guests_count] %>
            </p>
          </div>
          <!-- Availability Error Notice -->
          <div
            :if={@availability_error}
            class="bg-amber-50 border border-amber-200 rounded-lg p-4 mt-4"
          >
            <div class="flex items-start">
              <div class="flex-shrink-0">
                <.icon name="hero-exclamation-triangle" class="h-5 w-5 text-amber-600" />
              </div>
              <div class="ml-3">
                <h3 class="text-sm font-medium text-amber-800">Availability Issue</h3>
                <div class="mt-2 text-sm text-amber-700">
                  <p><%= @availability_error %></p>
                </div>
              </div>
            </div>
          </div>
          <!-- Reservation Summary & Price Display -->
          <div
            :if={@calculated_price && @checkin_date && @checkout_date}
            class="bg-zinc-50 rounded-md p-6 space-y-4"
          >
            <div>
              <h3 class="text-lg font-semibold text-zinc-900 mb-4">Reservation Summary</h3>
              <!-- Dates -->
              <div class="space-y-2 mb-4">
                <div class="flex items-center text-sm">
                  <span class="font-semibold text-zinc-700 w-24">Check-in:</span>
                  <span class="text-zinc-900">
                    <%= Calendar.strftime(@checkin_date, "%B %d, %Y") %>
                  </span>
                </div>
                <div class="flex items-center text-sm">
                  <span class="font-semibold text-zinc-700 w-24">Check-out:</span>
                  <span class="text-zinc-900">
                    <%= Calendar.strftime(@checkout_date, "%B %d, %Y") %>
                  </span>
                </div>
                <div class="flex items-center text-sm">
                  <span class="font-semibold text-zinc-700 w-24">Nights:</span>
                  <span class="text-zinc-900">
                    <%= Date.diff(@checkout_date, @checkin_date) %> night(s)
                  </span>
                </div>
              </div>
              <!-- Reservation Type Description -->
              <div class="bg-blue-50 border border-blue-200 rounded-md p-3 mb-4">
                <p class="text-sm text-blue-900">
                  <span :if={@selected_booking_mode == :day}>
                    <strong>A La Carte (Shared Stay):</strong>
                    You'll be sharing the cabin with other guests. Each guest pays per night, and you can book individual spots for up to 12 guests per day.
                  </span>
                  <span :if={@selected_booking_mode == :buyout}>
                    <strong>Full Buyout (Exclusive Rental):</strong>
                    You'll have the entire cabin exclusively for your group. Perfect for larger groups or special occasions!
                  </span>
                </p>
              </div>
              <!-- Price Breakdown -->
              <div class="border-t border-zinc-200 pt-4">
                <h4 class="text-sm font-semibold text-zinc-700 mb-3">Price Breakdown</h4>
                <div class="space-y-2 text-sm">
                  <span :if={@selected_booking_mode == :day}>
                    <% nights = Date.diff(@checkout_date, @checkin_date) %>
                    <% price_per_guest_per_night = Money.new(50, :USD) %>
                    <% total_guest_nights = nights * @guests_count %>
                    <div class="flex justify-between items-center">
                      <span class="text-zinc-600">
                        <%= @guests_count %> guest(s) × <%= nights %> night(s) × <%= MoneyHelper.format_money!(
                          price_per_guest_per_night
                        ) %> per guest/night
                      </span>
                      <span class="font-medium text-zinc-900">
                        <%= MoneyHelper.format_money!(
                          Money.mult(price_per_guest_per_night, total_guest_nights)
                          |> elem(1)
                        ) %>
                      </span>
                    </div>
                  </span>
                  <span :if={@selected_booking_mode == :buyout}>
                    <% nights = Date.diff(@checkout_date, @checkin_date) %>
                    <% price_per_night = Money.new(500, :USD) %>
                    <div class="flex justify-between items-center">
                      <span class="text-zinc-600">
                        <%= nights %> night(s) × <%= MoneyHelper.format_money!(price_per_night) %> per night
                      </span>
                      <span class="font-medium text-zinc-900">
                        <%= MoneyHelper.format_money!(Money.mult(price_per_night, nights) |> elem(1)) %>
                      </span>
                    </div>
                  </span>
                </div>
                <div class="flex justify-between items-center mt-4 pt-4 border-t border-zinc-300">
                  <span class="text-lg font-semibold text-zinc-900">Total Price:</span>
                  <span class="text-2xl font-bold text-blue-600">
                    <%= MoneyHelper.format_money!(@calculated_price) %>
                  </span>
                </div>
              </div>
            </div>
          </div>

          <p :if={@price_error} class="text-red-600 text-sm">
            <%= @price_error %>
          </p>
          <!-- Submit Button -->
          <div>
            <button
              :if={
                @can_book &&
                  can_submit_booking?(
                    @selected_booking_mode,
                    @checkin_date,
                    @checkout_date,
                    @guests_count,
                    @availability_error
                  )
              }
              phx-click="create-booking"
              class={[
                "w-full font-semibold py-3 px-4 rounded-md transition duration-200",
                if(@selected_booking_mode == :day,
                  do: "bg-blue-600 hover:bg-blue-700 text-white",
                  else: "bg-indigo-600 hover:bg-indigo-700 text-white"
                )
              ]}
            >
              <span :if={@selected_booking_mode == :day}>
                Confirm A La Carte Booking
              </span>
              <span :if={@selected_booking_mode == :buyout}>
                Confirm Full Cabin Buyout
              </span>
            </button>
            <div
              :if={!@can_book}
              class="w-full bg-zinc-300 text-zinc-600 font-semibold py-3 px-4 rounded-md text-center cursor-not-allowed"
            >
              Booking Unavailable
            </div>
          </div>
        </div>
        <!-- Information Tab Content -->
        <div
          :if={@active_tab == :information}
          class="space-y-8 prose prose-zinc px-4 lg:px-0 mx-auto lg:mx-0"
        >
          <style>
            details summary::-webkit-details-marker {
              display: none;
            }
            details summary .chevron-icon {
              transition: transform 0.2s ease-in-out;
            }
            details[open] summary .chevron-icon {
              transform: rotate(180deg);
            }
          </style>
          <!-- Welcome Header -->
          <div class="mb-8 prose prose-zinc">
            <p>
              Welcome to the <strong>Young Scandinavians Club Clear Lake Cabin</strong>, a slice of paradise on the shores of
              <strong>Clear Lake</strong>
              — California's largest natural lake.
            </p>
            <p>
              Located about <strong>2½ hours north of San Francisco</strong>, the cabin is open as a <strong>weekend destination from May through September</strong>, offering the perfect climate for lakeside relaxation and recreation.
            </p>
            <p>
              During the <strong>winter season</strong>, the cabin is available for <strong>full buyout only</strong>, set up with beds in the two front rooms and in the ladies' locker room.
            </p>
            <blockquote>
              <p>
                <strong>Tip:</strong>
                Many YSC summer events at Clear Lake include shared meals — check the event description for details on what's provided.
              </p>
            </blockquote>

            <YscWeb.Components.ImageCarousel.image_carousel
              id="about-the-clear-lake-cabin-carousel"
              images={[
                %{
                  src: ~p"/images/clear_lake/clear_lake_main.webp",
                  alt: "Clear Lake Cabin Exterior"
                },
                %{src: ~p"/images/clear_lake/clear_lake_dock.webp", alt: "Clear Lake Dock"},
                %{src: ~p"/images/clear_lake/clear_lake_dock_2.webp", alt: "Clear Lake Dock"},
                %{src: ~p"/images/clear_lake/clear_lake_sweep.webp", alt: "Clear Lake"},
                %{src: ~p"/images/clear_lake/clear_lake_cabin.webp", alt: "Clear Lake Cabin"}
              ]}
              class="my-8"
            />
          </div>
          <!-- Location & Directions (Collapsible) -->
          <details class="border border-zinc-200 rounded-lg p-4 bg-zinc-50">
            <summary class="cursor-pointer font-semibold text-lg text-zinc-900 mb-4 list-none flex items-center justify-between">
              <span class="flex items-center">
                <span class="mr-2">📍</span>
                <span>Location & Directions</span>
              </span>
              <.icon
                name="hero-chevron-down"
                class="w-5 h-5 text-zinc-500 chevron-icon flex-shrink-0"
              />
            </summary>
            <div>
              <div>
                <p class="font-semibold mb-2">Address:</p>
                <p class="mb-4">9325 Bass Road<br />Kelseyville, CA 95451</p>
                <p>
                  Public transportation options are very limited — <strong>driving is essential</strong>.
                </p>
              </div>

              <div class="flex flex-col items-center not-prose my-6">
                <.live_component
                  id="clear-lake-cabin-map"
                  module={YscWeb.Components.MapComponent}
                  latitude={38.98087180833886}
                  longitude={-122.73563627025182}
                  locked={true}
                  class="my-4"
                />
                <YscWeb.Components.MapNavigationButtons.map_navigation_buttons
                  latitude={38.98087180833886}
                  longitude={-122.73563627025182}
                  class="w-full"
                />
              </div>

              <div>
                <h3 class="font-semibold text-zinc-900 mb-2">Directions from San Francisco</h3>
                <ol class="list-decimal list-inside space-y-2">
                  <li>Take <strong>HWY 101 North</strong> past Santa Rosa.</li>
                  <li>Exit at <strong>River Road / Guerneville (Exit 494)</strong>.</li>
                  <li>
                    Turn <strong>right onto Mark West Springs Rd</strong>
                    (becomes Porter Creek Rd) — go 10.5 miles until it ends.
                  </li>
                  <li>
                    Turn <strong>left</strong>
                    at the stop sign onto <strong>Petrified Forest Rd</strong>
                    toward Calistoga — continue 4.6 miles.
                  </li>
                  <li>
                    Turn <strong>left</strong>
                    at the stop sign onto <strong>Foothill Blvd / HWY 128</strong>
                    — go 0.8 miles.
                  </li>
                  <li>
                    Turn <strong>right</strong>
                    onto <strong>Tubbs Lane</strong>
                    — go 1.3 miles to the end.
                  </li>
                  <li>
                    Turn <strong>left</strong>
                    onto <strong>HWY 29</strong>
                    — go 28 miles over Mt. St. Helena through Middletown to the stoplight in Lower Lake.
                  </li>
                  <li>
                    Turn <strong>left</strong>
                    onto <strong>HWY 29</strong>
                    at Lower Lake (Shell Station on left) — go 7.5 miles.
                  </li>
                  <li>
                    Turn <strong>right</strong>
                    onto <strong>Soda Bay Road / HWY 281</strong>
                    (Kits Corner Store on right) — go 4.3 miles.
                  </li>
                  <li>
                    Turn <strong>right</strong>
                    onto <strong>Bass Road</strong>
                    (just after Montezuma Way and a church) — go 0.3 miles.
                  </li>
                  <li>
                    Turn <strong>right</strong>
                    at the <strong>third driveway with the YSC sign</strong>.
                  </li>
                </ol>
                <blockquote class="mt-4">
                  <p>
                    <strong>Note:</strong>
                    If you reach Konocti Harbor Inn, you've gone too far — turn around.
                  </p>
                </blockquote>
              </div>
            </div>
          </details>
          <!-- Parking (Collapsible) -->
          <details class="border border-zinc-200 rounded-lg p-4 bg-zinc-50">
            <summary class="cursor-pointer font-semibold text-lg text-zinc-900 mb-4 list-none flex items-center justify-between">
              <span class="flex items-center">
                <span class="mr-2">🅿️</span>
                <span>Parking</span>
              </span>
              <.icon
                name="hero-chevron-down"
                class="w-5 h-5 text-zinc-500 chevron-icon flex-shrink-0"
              />
            </summary>
            <div>
              <p>Parking is limited, so please:</p>
              <ul>
                <li>Park as close to the next car as possible.</li>
                <li>
                  Choose your spot based on <strong>when you plan to leave</strong>
                  — otherwise you may be blocked in on Sunday morning.
                </li>
              </ul>
            </div>
          </details>
          <!-- Accommodations (Collapsible) -->
          <details class="border border-zinc-200 rounded-lg p-4 bg-zinc-50">
            <summary class="cursor-pointer font-semibold text-lg text-zinc-900 mb-4 list-none flex items-center justify-between">
              <span class="flex items-center">
                <span class="mr-2">🏕️</span>
                <span>Accommodations</span>
              </span>
              <.icon
                name="hero-chevron-down"
                class="w-5 h-5 text-zinc-500 chevron-icon flex-shrink-0"
              />
            </summary>
            <div>
              <p>Enjoy a true <strong>lakeside camping experience</strong>!</p>
              <p class="font-semibold mt-4 mb-2">You can:</p>
              <ul>
                <li>
                  <strong>Sleep under the stars</strong> on the main lawn (mattresses provided)
                </li>
                <li>
                  <strong>Pitch a tent</strong> on the back lawn
                </li>
              </ul>
              <blockquote class="mt-4">
                <p>
                  <strong>⛺ Tent space is limited</strong>
                  — please avoid bringing large tents on busy weekends.
                </p>
              </blockquote>
              <p>
                California's dry, mosquito-free summer nights make sleeping outdoors a treat.
              </p>
              <p class="text-sm mt-2">
                <strong>Note:</strong>
                Lawn sprinklers run at 4 AM on Mondays, Tuesdays, and Wednesdays.
              </p>
            </div>
          </details>
          <!-- Water (Collapsible) -->
          <details class="border border-zinc-200 rounded-lg p-4 bg-zinc-50">
            <summary class="cursor-pointer font-semibold text-lg text-zinc-900 mb-4 list-none flex items-center justify-between">
              <span class="flex items-center">
                <span class="mr-2">💧</span>
                <span>Water</span>
              </span>
              <.icon
                name="hero-chevron-down"
                class="w-5 h-5 text-zinc-500 chevron-icon flex-shrink-0"
              />
            </summary>
            <div>
              <p>
                Tap water at the cabin is <strong>safe to drink</strong>.
              </p>
              <p>
                Many members bring a cooler with <strong>ice, bottled water, and drinks</strong>, as the nearest store is about
                <strong>5 miles (8 km)</strong>
                away.
              </p>
              <p class="mt-4">
                <a href="#" target="_blank" class="text-blue-600 hover:text-blue-800 underline">
                  Water System Operations Manual
                </a>
                <span class="text-sm text-zinc-500"> (link if available)</span>
              </p>
            </div>
          </details>
          <!-- What to Bring (Collapsible) -->
          <details class="border border-zinc-200 rounded-lg p-4 bg-zinc-50">
            <summary class="cursor-pointer font-semibold text-lg text-zinc-900 mb-4 list-none flex items-center justify-between">
              <span class="flex items-center">
                <span class="mr-2">🎒</span>
                <span>What to Bring</span>
              </span>
              <.icon
                name="hero-chevron-down"
                class="w-5 h-5 text-zinc-500 chevron-icon flex-shrink-0"
              />
            </summary>
            <div>
              <p class="font-semibold mb-2">Bring these essentials:</p>
              <ul>
                <li>Sleeping bag and pillow</li>
                <li>Towel and swimsuit</li>
                <li>Sunscreen and flip-flops</li>
                <li>Cooler with ice and beverages</li>
                <li>Anything else you need for lakeside fun!</li>
              </ul>
              <p class="font-semibold mt-4 mb-2">
                If you're attending a <strong>YSC event</strong>, you might also want:
              </p>
              <ul>
                <li>
                  <strong>Dancing shoes</strong> 💃
                </li>
                <li>
                  <strong>Earplugs</strong> (if you're turning in early)
                </li>
              </ul>
            </div>
          </details>
          <!-- Boating (Collapsible) -->
          <details class="border border-zinc-200 rounded-lg p-4 bg-zinc-50">
            <summary class="cursor-pointer font-semibold text-lg text-zinc-900 mb-4 list-none flex items-center justify-between">
              <span class="flex items-center">
                <span class="mr-2">🛶</span>
                <span>Boating</span>
              </span>
              <.icon
                name="hero-chevron-down"
                class="w-5 h-5 text-zinc-500 chevron-icon flex-shrink-0"
              />
            </summary>
            <div>
              <p>Private boats are welcome!</p>
              <ul>
                <li>No overnight mooring fee.</li>
                <li>
                  Please <strong>notify the Cabin Master in advance</strong> so space can be arranged.
                </li>
                <li>
                  Boat trailers <strong>cannot be parked</strong> on YSC grounds.
                </li>
              </ul>
              <p class="mt-4">
                All boats must comply with the <strong>Invasive Mussel Prevention Program</strong>
                — fines up to <strong>$1,000</strong>
                apply for non-compliance.
              </p>
            </div>
          </details>
          <!-- Quiet Hours (Collapsible) -->
          <details class="border border-zinc-200 rounded-lg p-4 bg-zinc-50">
            <summary class="cursor-pointer font-semibold text-lg text-zinc-900 mb-4 list-none flex items-center justify-between">
              <span class="flex items-center">
                <span class="mr-2">🌙</span>
                <span>Quiet Hours</span>
              </span>
              <.icon
                name="hero-chevron-down"
                class="w-5 h-5 text-zinc-500 chevron-icon flex-shrink-0"
              />
            </summary>
            <div>
              <ul>
                <li>
                  <strong>All lights and music must be turned off by midnight.</strong>
                </li>
                <li>
                  This rule may be waived for <strong>special party weekends</strong>
                  — see event details for exceptions.
                </li>
              </ul>
            </div>
          </details>
          <!-- General Responsibilities (Collapsible) -->
          <details class="border border-zinc-200 rounded-lg p-4 bg-zinc-50">
            <summary class="cursor-pointer font-semibold text-lg text-zinc-900 mb-4 list-none flex items-center justify-between">
              <span class="flex items-center">
                <span class="mr-2">🧹</span>
                <span>General Responsibilities</span>
              </span>
              <.icon
                name="hero-chevron-down"
                class="w-5 h-5 text-zinc-500 chevron-icon flex-shrink-0"
              />
            </summary>
            <div>
              <p>Everyone helps make each stay a success!</p>
              <ul>
                <li>
                  Upon arrival, all guests must <strong>sign up for a chore</strong>.
                </li>
                <li>
                  Clear Lake events rely on <strong>every member contributing</strong>.
                </li>
              </ul>
            </div>
          </details>
          <!-- Code of Conduct (Collapsible) -->
          <details class="border border-zinc-200 rounded-lg p-4 bg-zinc-50">
            <summary class="cursor-pointer font-semibold text-lg text-zinc-900 mb-4 list-none flex items-center justify-between">
              <span class="flex items-center">
                <span class="mr-2">📜</span>
                <span>Code of Conduct</span>
              </span>
              <.icon
                name="hero-chevron-down"
                class="w-5 h-5 text-zinc-500 chevron-icon flex-shrink-0"
              />
            </summary>
            <div>
              <p>
                Everyone attending YSC events or visiting club properties should enjoy a <strong>safe, welcoming, and inclusive environment</strong>.
              </p>
              <p>
                Any behavior that is discriminatory, harassing, or threatening is <strong>strictly prohibited</strong>.
              </p>
              <p class="mt-4">
                The <strong>Cabin Master</strong>
                or <strong>event host</strong>
                may determine if conduct violates this policy.
              </p>
              <ul class="mt-4">
                <li>
                  <a
                    href="https://ysc.org/non-discrimination-code-of-conduct/"
                    target="_blank"
                    class="text-blue-600 hover:text-blue-800 underline"
                  >
                    View the YSC Code of Conduct
                  </a>
                </li>
                <li>
                  <a
                    href="https://ysc.org/conduct-violation-report-form/"
                    target="_blank"
                    class="text-blue-600 hover:text-blue-800 underline"
                  >
                    Report a Conduct Violation
                  </a>
                </li>
              </ul>
            </div>
          </details>
          <!-- Children (Collapsible) -->
          <details class="border border-zinc-200 rounded-lg p-4 bg-zinc-50">
            <summary class="cursor-pointer font-semibold text-lg text-zinc-900 mb-4 list-none flex items-center justify-between">
              <span class="flex items-center">
                <span class="mr-2">👨‍👩‍👧</span>
                <span>Children</span>
              </span>
              <.icon
                name="hero-chevron-down"
                class="w-5 h-5 text-zinc-500 chevron-icon flex-shrink-0"
              />
            </summary>
            <div>
              <p>
                Clear Lake is <strong>family-friendly</strong>
                and ideal for children on most weekends.
              </p>
              <p>
                However, <strong>some party weekends may not be suitable</strong>
                for kids — refer to event descriptions for guidance.
              </p>
            </div>
          </details>
          <!-- Pets (Collapsible) -->
          <details class="border border-zinc-200 rounded-lg p-4 bg-zinc-50">
            <summary class="cursor-pointer font-semibold text-lg text-zinc-900 mb-4 list-none flex items-center justify-between">
              <span class="flex items-center">
                <span class="mr-2">🐾</span>
                <span>Pets</span>
              </span>
              <.icon
                name="hero-chevron-down"
                class="w-5 h-5 text-zinc-500 chevron-icon flex-shrink-0"
              />
            </summary>
            <div>
              <p>
                Dogs and other pets are <strong>not allowed</strong>
                anywhere on YSC properties, including the <strong>Clear Lake campground</strong>.
              </p>
            </div>
          </details>
          <!-- Non-Member Guests (Collapsible) -->
          <details class="border border-zinc-200 rounded-lg p-4 bg-zinc-50">
            <summary class="cursor-pointer font-semibold text-lg text-zinc-900 mb-4 list-none flex items-center justify-between">
              <span class="flex items-center">
                <span class="mr-2">🧍‍♂️</span>
                <span>Non-Member Guests</span>
              </span>
              <.icon
                name="hero-chevron-down"
                class="w-5 h-5 text-zinc-500 chevron-icon flex-shrink-0"
              />
            </summary>
            <div>
              <p>Guests are welcome on general visits, but:</p>
              <ul>
                <li>
                  All guests must be <strong>included in and paid for</strong>
                  by the member making the reservation.
                </li>
                <li>
                  Certain events may have <strong>guest restrictions</strong>
                  — check event details for specifics.
                </li>
              </ul>
            </div>
          </details>
          <!-- Cabin Facilities (Collapsible) -->
          <details class="border border-zinc-200 rounded-lg p-4 bg-zinc-50">
            <summary class="cursor-pointer font-semibold text-lg text-zinc-900 mb-4 list-none flex items-center justify-between">
              <span class="flex items-center">
                <span class="mr-2">🏡</span>
                <span>Cabin Facilities</span>
              </span>
              <.icon
                name="hero-chevron-down"
                class="w-5 h-5 text-zinc-500 chevron-icon flex-shrink-0"
              />
            </summary>
            <div>
              <p>The Clear Lake cabin includes:</p>
              <ul>
                <li>A large <strong>kitchen</strong></li>
                <li>
                  <strong>Men's and women's bathrooms</strong> and changing rooms
                </li>
                <li>
                  A <strong>living room / dance floor</strong> for gatherings and events
                </li>
              </ul>
            </div>
          </details>
          <!-- Things to Do Nearby (Collapsible) -->
          <details class="border border-zinc-200 rounded-lg p-4 bg-zinc-50">
            <summary class="cursor-pointer font-semibold text-lg text-zinc-900 mb-4 list-none flex items-center justify-between">
              <span class="flex items-center">
                <span class="mr-2">🌄</span>
                <span>Things to Do Nearby</span>
              </span>
              <.icon
                name="hero-chevron-down"
                class="w-5 h-5 text-zinc-500 chevron-icon flex-shrink-0"
              />
            </summary>
            <div>
              <p>
                While the cabin offers plenty of on-site fun, consider exploring these local attractions:
              </p>
              <ul>
                <li>
                  <a
                    href="https://lakecounty.com"
                    target="_blank"
                    class="text-blue-600 hover:text-blue-800 underline"
                  >
                    Lake County Tourism Board
                  </a>
                </li>
                <li>
                  <a
                    href="https://www.konoctitrails.com"
                    target="_blank"
                    class="text-blue-600 hover:text-blue-800 underline"
                  >
                    Konocti Trails – Hiking Mount Konocti
                  </a>
                </li>
                <li>
                  <a
                    href="https://www.parks.ca.gov/?page_id=473"
                    target="_blank"
                    class="text-blue-600 hover:text-blue-800 underline"
                  >
                    Clear Lake State Park
                  </a>
                </li>
                <li>
                  <a
                    href="https://lakecountywineries.org"
                    target="_blank"
                    class="text-blue-600 hover:text-blue-800 underline"
                  >
                    Lake County Wine Tasting
                  </a>
                  — visit one of a dozen nearby wineries!
                </li>
              </ul>
            </div>
          </details>
          <!-- Quick Booking Reference -->
          <div>
            <h2>📋 Quick Booking Reference</h2>
            <div class="overflow-x-auto px-4">
              <table class="w-full border-collapse">
                <thead>
                  <tr class="border-b border-zinc-300">
                    <th class="text-left py-2 pr-4 font-semibold text-zinc-900">Rule</th>
                    <th class="text-left py-2 font-semibold text-zinc-900">Details</th>
                  </tr>
                </thead>
                <tbody class="text-zinc-700">
                  <tr class="border-b border-zinc-200">
                    <td class="py-2 pr-4 font-semibold">Check-In / Out</td>
                    <td class="py-2">3:00 PM / 11:00 AM</td>
                  </tr>
                  <tr class="border-b border-zinc-200">
                    <td class="py-2 pr-4 font-semibold">Booking Type</td>
                    <td class="py-2">By number of guests (not rooms)</td>
                  </tr>
                  <tr class="border-b border-zinc-200">
                    <td class="py-2 pr-4 font-semibold">Pricing</td>
                    <td class="py-2">Per guest, per day</td>
                  </tr>
                  <tr class="border-b border-zinc-200">
                    <td class="py-2 pr-4 font-semibold">Maximum Capacity</td>
                    <td class="py-2"><%= @max_guests %> guests per day</td>
                  </tr>
                  <tr class="border-b border-zinc-200">
                    <td class="py-2 pr-4 font-semibold">Children (≤5 years)</td>
                    <td class="py-2">Free (do not include in guest count)</td>
                  </tr>
                  <tr>
                    <td class="py-2 pr-4 font-semibold">Full Buyout Option</td>
                    <td class="py-2">Available during winter season</td>
                  </tr>
                </tbody>
              </table>
            </div>
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
        calculated_price: nil,
        price_error: nil,
        form_errors: %{},
        date_form: date_form
      )
      |> calculate_price_if_ready()
      |> update_url_with_dates(checkin_date, checkout_date)

    {:noreply, socket}
  end

  def handle_event("date-changed", %{"checkin_date" => checkin_date_str}, socket) do
    checkin_date = parse_date(checkin_date_str)
    # Preserve existing checkout_date
    checkout_date = socket.assigns.checkout_date

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
        calculated_price: nil,
        price_error: nil,
        form_errors: %{},
        date_form: date_form
      )
      |> calculate_price_if_ready()
      |> update_url_with_dates(checkin_date, checkout_date)

    {:noreply, socket}
  end

  def handle_event("date-changed", %{"checkout_date" => checkout_date_str}, socket) do
    checkout_date = parse_date(checkout_date_str)
    # Preserve existing checkin_date
    checkin_date = socket.assigns.checkin_date

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
        calculated_price: nil,
        price_error: nil,
        form_errors: %{},
        date_form: date_form
      )
      |> calculate_price_if_ready()
      |> update_url_with_dates(checkin_date, checkout_date)

    {:noreply, socket}
  end

  def handle_event("booking-mode-changed", %{"booking_mode" => "day"}, socket) do
    # Re-check allowed booking modes based on current dates
    {day_booking_allowed, buyout_booking_allowed} =
      allowed_booking_modes(
        socket.assigns.property,
        socket.assigns.checkin_date,
        socket.assigns.checkout_date,
        socket.assigns.current_season
      )

    # Validate availability for the new booking mode if dates are selected
    availability_error =
      if socket.assigns.checkin_date && socket.assigns.checkout_date do
        validate_date_range_for_booking_mode(
          socket.assigns.checkin_date,
          socket.assigns.checkout_date,
          :day,
          socket.assigns.guests_count,
          socket.assigns
        )
      else
        nil
      end

    socket =
      socket
      |> assign(
        selected_booking_mode: :day,
        calculated_price: nil,
        price_error: nil,
        availability_error: availability_error,
        day_booking_allowed: day_booking_allowed,
        buyout_booking_allowed: buyout_booking_allowed
      )
      |> calculate_price_if_ready()
      |> then(fn updated_socket ->
        # Update URL with new booking mode
        update_url_with_booking_mode(updated_socket)
      end)

    {:noreply, socket}
  end

  def handle_event("booking-mode-changed", %{"booking_mode" => "buyout"}, socket) do
    # Re-check allowed booking modes based on current dates
    {day_booking_allowed, buyout_booking_allowed} =
      allowed_booking_modes(
        socket.assigns.property,
        socket.assigns.checkin_date,
        socket.assigns.checkout_date,
        socket.assigns.current_season
      )

    # Validate availability for the new booking mode if dates are selected
    availability_error =
      if socket.assigns.checkin_date && socket.assigns.checkout_date do
        validate_date_range_for_booking_mode(
          socket.assigns.checkin_date,
          socket.assigns.checkout_date,
          :buyout,
          socket.assigns.guests_count,
          socket.assigns
        )
      else
        nil
      end

    socket =
      socket
      |> assign(
        selected_booking_mode: :buyout,
        calculated_price: nil,
        price_error: nil,
        availability_error: availability_error,
        day_booking_allowed: day_booking_allowed,
        buyout_booking_allowed: buyout_booking_allowed
      )
      |> calculate_price_if_ready()
      |> then(fn updated_socket ->
        # Update URL with new booking mode
        update_url_with_booking_mode(updated_socket)
      end)

    {:noreply, socket}
  end

  def handle_event("guests-changed", %{"guests_count" => guests_str}, socket) do
    guests_count = parse_integer(guests_str) || 1

    # Validate that guests_count is within valid range
    guests_count = min(max(guests_count, 1), @max_guests)

    # Check if the selected dates still have enough spots available
    availability_error =
      if socket.assigns.selected_booking_mode == :day &&
           socket.assigns.checkin_date &&
           socket.assigns.checkout_date do
        validate_guests_against_availability(
          socket.assigns.checkin_date,
          socket.assigns.checkout_date,
          guests_count,
          socket.assigns
        )
      else
        nil
      end

    socket =
      socket
      |> assign(
        guests_count: guests_count,
        calculated_price: nil,
        price_error: nil,
        availability_error: availability_error
      )
      |> calculate_price_if_ready()
      |> then(fn updated_socket ->
        # Always update URL when guests change, even if dates are nil
        # This ensures guests_count is preserved in the URL
        update_url_with_guests(updated_socket)
      end)

    {:noreply, socket}
  end

  def handle_event("reset-dates", _params, socket) do
    date_form =
      to_form(
        %{
          "checkin_date" => "",
          "checkout_date" => ""
        },
        as: "booking_dates"
      )

    socket =
      socket
      |> assign(
        checkin_date: nil,
        checkout_date: nil,
        calculated_price: nil,
        price_error: nil,
        availability_error: nil,
        date_form: date_form
      )
      |> update_url_with_dates(nil, nil)

    {:noreply, socket}
  end

  def handle_event("create-booking", _params, socket) do
    case validate_and_create_booking(socket) do
      {:ok, booking} ->
        {:noreply,
         socket
         |> push_navigate(to: ~p"/bookings/checkout/#{booking.id}")}

      {:error, :insufficient_capacity} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Sorry, there is not enough capacity for your requested dates and number of guests."
         )
         |> assign(
           form_errors: %{
             general:
               "Sorry, there is not enough capacity for your requested dates and number of guests."
           },
           calculated_price: socket.assigns.calculated_price,
           availability_error: "Not enough capacity available"
         )}

      {:error, :property_unavailable} ->
        {:noreply,
         socket
         |> put_flash(:error, "Sorry, the property is not available for your requested dates.")
         |> assign(
           form_errors: %{
             general: "Sorry, the property is not available for your requested dates."
           },
           calculated_price: socket.assigns.calculated_price,
           availability_error: "Property unavailable"
         )}

      {:error, reason} when is_atom(reason) ->
        error_message = format_booking_error(reason)

        {:noreply,
         socket
         |> put_flash(:error, error_message)
         |> assign(
           form_errors: %{general: error_message},
           calculated_price: socket.assigns.calculated_price
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        form_errors = format_errors(changeset)
        error_message = "Please fix the errors above and try again."

        {:noreply,
         socket
         |> put_flash(:error, error_message)
         |> assign(
           form_errors: form_errors,
           calculated_price: nil,
           price_error: "Please fix the errors above"
         )}

      {:error, {:error, %Ecto.Changeset{} = changeset}} ->
        # Handle nested error from Repo.rollback({:error, changeset})
        form_errors = format_errors(changeset)
        error_message = "Please fix the errors above and try again."

        {:noreply,
         socket
         |> put_flash(:error, error_message)
         |> assign(
           form_errors: form_errors,
           calculated_price: nil,
           price_error: "Please fix the errors above"
         )}

      {:error, {:error, reason}} when is_atom(reason) ->
        # Handle nested error from Repo.rollback({:error, reason})
        error_message = format_booking_error(reason)

        {:noreply,
         socket
         |> put_flash(:error, error_message)
         |> assign(
           form_errors: %{general: error_message},
           calculated_price: socket.assigns.calculated_price
         )}
    end
  end

  def handle_event("switch-tab", %{"tab" => tab}, socket) do
    active_tab =
      case tab do
        "information" ->
          :information

        "booking" ->
          # Prevent switching to booking tab if user can't book
          if socket.assigns.can_book do
            :booking
          else
            socket.assigns.active_tab
          end

        _ ->
          socket.assigns.active_tab
      end

    # Only update if tab actually changed
    if active_tab != socket.assigns.active_tab do
      # Update URL with the new tab
      query_params =
        build_query_params(
          socket.assigns.checkin_date,
          socket.assigns.checkout_date,
          socket.assigns.guests_count,
          active_tab,
          socket.assigns.selected_booking_mode || :day
        )

      socket =
        socket
        |> assign(active_tab: active_tab)
        |> push_patch(to: ~p"/bookings/clear-lake?#{URI.encode_query(query_params)}")

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(
        {:availability_calendar_date_changed,
         %{checkin_date: checkin_date, checkout_date: checkout_date}},
        socket
      ) do
    date_form =
      to_form(
        %{
          "checkin_date" => date_to_datetime_string(checkin_date),
          "checkout_date" => date_to_datetime_string(checkout_date)
        },
        as: "booking_dates"
      )

    # Validate availability when dates change
    availability_error =
      if socket.assigns.selected_booking_mode == :day &&
           checkin_date &&
           checkout_date &&
           socket.assigns.guests_count do
        validate_guests_against_availability(
          checkin_date,
          checkout_date,
          socket.assigns.guests_count,
          socket.assigns
        )
      else
        nil
      end

    # Re-check allowed booking modes based on new dates
    {day_booking_allowed, buyout_booking_allowed} =
      allowed_booking_modes(
        socket.assigns.property,
        checkin_date,
        checkout_date,
        socket.assigns.current_season
      )

    socket =
      socket
      |> assign(
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        calculated_price: nil,
        price_error: nil,
        availability_error: availability_error,
        form_errors: %{},
        date_form: date_form,
        day_booking_allowed: day_booking_allowed,
        buyout_booking_allowed: buyout_booking_allowed
      )
      |> calculate_price_if_ready()
      |> update_url_with_dates(checkin_date, checkout_date)

    {:noreply, socket}
  end

  def handle_info({:availability_calendar_date_changed, _}, socket) do
    {:noreply, socket}
  end

  # Helper functions

  defp parse_date(""), do: nil
  defp parse_date(date_str) when is_binary(date_str), do: Date.from_iso8601!(date_str)
  defp parse_date(_), do: nil

  defp parse_integer(""), do: nil
  defp parse_integer(int_str) when is_binary(int_str), do: String.to_integer(int_str)
  defp parse_integer(_), do: nil

  defp calculate_price_if_ready(socket) do
    PricingHelpers.calculate_price_if_ready(socket, :clear_lake)
  end

  defp can_submit_booking?(
         booking_mode,
         checkin_date,
         checkout_date,
         guests_count,
         availability_error
       ) do
    checkin_date && checkout_date &&
      is_nil(availability_error) &&
      (booking_mode == :buyout ||
         (booking_mode == :day && guests_count > 0 && guests_count <= @max_guests))
  end

  defp validate_and_create_booking(socket) do
    property = socket.assigns.property
    checkin_date = socket.assigns.checkin_date
    checkout_date = socket.assigns.checkout_date
    booking_mode = socket.assigns.selected_booking_mode
    guests_count = socket.assigns.guests_count
    user_id = socket.assigns.user.id

    # Validate required fields
    if is_nil(checkin_date) || is_nil(checkout_date) || is_nil(guests_count) || guests_count <= 0 do
      {:error, :invalid_parameters}
    else
      # Use BookingLocker to create booking with inventory locking
      case booking_mode do
        :buyout ->
          BookingLocker.create_buyout_booking(
            user_id,
            property,
            checkin_date,
            checkout_date,
            guests_count
          )

        :day ->
          BookingLocker.create_per_guest_booking(
            user_id,
            property,
            checkin_date,
            checkout_date,
            guests_count
          )

        _ ->
          {:error, :invalid_booking_mode}
      end
    end
  end

  defp format_booking_error(:insufficient_capacity),
    do: "Sorry, there is not enough capacity for your requested dates and number of guests."

  defp format_booking_error(:property_unavailable),
    do: "Sorry, the property is not available for your requested dates."

  defp format_booking_error(:stale_inventory),
    do:
      "The availability changed while you were booking. Please refresh the calendar and try again."

  defp format_booking_error(:rooms_already_booked),
    do: "Sorry, some rooms are already booked for your requested dates."

  defp format_booking_error(:invalid_parameters),
    do: "Please fill in all required fields."

  defp format_booking_error(:invalid_booking_mode),
    do: "Invalid booking mode selected."

  defp format_booking_error(_),
    do: "An error occurred while creating your booking. Please try again."

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp check_booking_eligibility(nil) do
    sign_in_path = ~p"/users/log-in"

    sign_in_link =
      ~s(<a href="#{sign_in_path}" class="font-semibold text-amber-900 hover:text-amber-950 underline">sign in</a>)

    {
      false,
      "You must be signed in to make a booking. Please #{sign_in_link} to continue."
    }
  end

  defp check_booking_eligibility(user) do
    # Check if user account is approved
    if user.state != :active do
      {
        false,
        "Your membership application is pending approval. You will be able to make bookings once your application has been approved."
      }
    else
      # Check if user has active membership
      user_with_subs =
        case user.subscriptions do
          %Ecto.Association.NotLoaded{} ->
            Accounts.get_user!(user.id)
            |> Ysc.Repo.preload(:subscriptions)

          _ ->
            user
        end

      if Accounts.has_active_membership?(user_with_subs) do
        {true, nil}
      else
        {
          false,
          "You need an active membership to make bookings. Please activate or renew your membership to continue."
        }
      end
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

  defp date_to_datetime_string(nil), do: ""

  defp date_to_datetime_string(date) when is_struct(date, Date) do
    date
    |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    |> DateTime.to_iso8601()
  end

  defp parse_query_params(params, _uri) when is_map(params) do
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

  defp parse_query_params(_params, uri) do
    # If params is not a map, try to parse from URI
    case URI.parse(uri) do
      %URI{query: nil} -> %{}
      %URI{query: query} -> parse_query_string(query)
      _ -> %{}
    end
  end

  defp find_malformed_query_key(params) when is_map(params) do
    Enum.find_value(params, fn {key, _value} ->
      if is_binary(key) and String.contains?(key, "=") do
        key
      else
        nil
      end
    end)
  end

  defp find_malformed_query_key(_), do: nil

  defp parse_query_string(nil), do: %{}
  defp parse_query_string(""), do: %{}

  defp parse_query_string(query_string) when is_binary(query_string) do
    query_string
    |> URI.decode_query()
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

  defp parse_tab_from_params(params) do
    case Map.get(params, "tab") do
      "information" -> :information
      "booking" -> :booking
      _ -> :booking
    end
  end

  defp parse_booking_mode_from_params(params) do
    case Map.get(params, "booking_mode") do
      "buyout" -> :buyout
      "day" -> :day
      _ -> nil
    end
  end

  defp resolve_booking_mode(mode, day_allowed, buyout_allowed) do
    cond do
      # If mode is explicitly valid, use it
      mode == :day && day_allowed ->
        :day

      mode == :buyout && buyout_allowed ->
        :buyout

      # If mode is nil (default), prefer day if allowed, else buyout
      is_nil(mode) ->
        if day_allowed, do: :day, else: :buyout

      # If mode is invalid (e.g. day requested but not allowed), try the other
      mode == :day && buyout_allowed ->
        :buyout

      mode == :buyout && day_allowed ->
        :day

      # If nothing works, just return day (error will likely be shown elsewhere)
      true ->
        :day
    end
  end

  defp update_url_with_dates(socket, checkin_date, checkout_date) do
    guests_count = socket.assigns.guests_count || 1
    active_tab = socket.assigns.active_tab || :booking
    booking_mode = socket.assigns.selected_booking_mode || :day

    query_params =
      build_query_params(checkin_date, checkout_date, guests_count, active_tab, booking_mode)

    if map_size(query_params) > 0 do
      query_string = URI.encode_query(query_params)
      push_patch(socket, to: "/bookings/clear-lake?#{query_string}")
    else
      push_patch(socket, to: ~p"/bookings/clear-lake")
    end
  end

  defp update_url_with_guests(socket) do
    checkin_date = socket.assigns.checkin_date
    checkout_date = socket.assigns.checkout_date
    guests_count = socket.assigns.guests_count || 1
    active_tab = socket.assigns.active_tab || :booking
    booking_mode = socket.assigns.selected_booking_mode || :day

    query_params =
      build_query_params(checkin_date, checkout_date, guests_count, active_tab, booking_mode)

    if map_size(query_params) > 0 do
      query_string = URI.encode_query(query_params)
      push_patch(socket, to: "/bookings/clear-lake?#{query_string}")
    else
      push_patch(socket, to: ~p"/bookings/clear-lake")
    end
  end

  defp update_url_with_booking_mode(socket) do
    checkin_date = socket.assigns.checkin_date
    checkout_date = socket.assigns.checkout_date
    guests_count = socket.assigns.guests_count || 1
    active_tab = socket.assigns.active_tab || :booking
    booking_mode = socket.assigns.selected_booking_mode || :day

    query_params =
      build_query_params(checkin_date, checkout_date, guests_count, active_tab, booking_mode)

    if map_size(query_params) > 0 do
      query_string = URI.encode_query(query_params)
      push_patch(socket, to: "/bookings/clear-lake?#{query_string}")
    else
      push_patch(socket, to: ~p"/bookings/clear-lake")
    end
  end

  defp build_query_params(checkin_date, checkout_date, guests_count, active_tab, booking_mode) do
    params = %{}

    # Always include dates when they are set
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

    # Always include guests_count when it's set
    params =
      if guests_count do
        Map.put(params, "guests_count", Integer.to_string(guests_count))
      else
        params
      end

    # Include booking_mode when it's not the default (:day)
    params =
      if booking_mode && booking_mode != :day do
        Map.put(params, "booking_mode", Atom.to_string(booking_mode))
      else
        params
      end

    # Include tab when it's not the default (:booking)
    params =
      if active_tab && active_tab != :booking do
        Map.put(params, "tab", Atom.to_string(active_tab))
      else
        params
      end

    params
  end

  # Validates that the selected date range is available for the given booking mode
  defp validate_date_range_for_booking_mode(
         checkin_date,
         checkout_date,
         booking_mode,
         guests_count,
         assigns
       ) do
    # Create a temporary assigns with the booking mode to reuse existing validation logic
    temp_assigns = Map.put(assigns, :selected_booking_mode, booking_mode)
    validate_guests_against_availability(checkin_date, checkout_date, guests_count, temp_assigns)
  end

  # Validates that the selected dates have enough spots available for the requested number of guests
  defp validate_guests_against_availability(checkin_date, checkout_date, guests_count, assigns) do
    # Get availability for the date range
    availability = Bookings.get_clear_lake_daily_availability(checkin_date, checkout_date)

    # Check each date in the range, but exclude checkout_date
    # Since checkout is at 11 AM and check-in is at 3 PM, the checkout_date
    # is not an occupied night and should not be validated
    date_range =
      if Date.compare(checkout_date, checkin_date) == :gt do
        # Exclude checkout_date - only validate nights that will be stayed
        Date.range(checkin_date, Date.add(checkout_date, -1)) |> Enum.to_list()
      else
        # Edge case: same day check-in/check-out (shouldn't happen, but handle gracefully)
        []
      end

    unavailable_dates =
      date_range
      |> Enum.filter(fn date ->
        day_availability = Map.get(availability, date)

        if day_availability do
          # Check if there are enough spots available
          if day_availability.is_blacked_out do
            true
          else
            if assigns[:selected_booking_mode] == :day do
              # For day bookings, check if there are enough spots
              day_availability.spots_available < guests_count
            else
              # For buyout, check if buyout is possible
              not day_availability.can_book_buyout
            end
          end
        else
          # Date not in availability map - assume unavailable
          true
        end
      end)

    if Enum.empty?(unavailable_dates) do
      nil
    else
      # Build error message
      if length(unavailable_dates) == 1 do
        date_str = unavailable_dates |> List.first() |> Date.to_string()
        day_availability = Map.get(availability, List.first(unavailable_dates))

        cond do
          day_availability && day_availability.is_blacked_out ->
            "The date #{date_str} is blacked out and cannot be booked."

          day_availability && assigns[:selected_booking_mode] == :day ->
            spots = day_availability.spots_available

            "The date #{date_str} only has #{spots} spot#{if spots == 1, do: "", else: "s"} available, but you're trying to book #{guests_count} guest#{if guests_count == 1, do: "", else: "s"}."

          day_availability && assigns[:selected_booking_mode] == :buyout ->
            "The date #{date_str} cannot be booked as a buyout (there are existing day bookings)."

          true ->
            "The date #{date_str} is unavailable for your selected number of guests."
        end
      else
        dates_str =
          unavailable_dates
          |> Enum.map(&Date.to_string/1)
          |> Enum.join(", ")

        if assigns[:selected_booking_mode] == :buyout do
          "The following dates in your selection cannot be booked as a buyout because there are existing day bookings: #{dates_str}. Please select different dates or switch to A La Carte booking mode."
        else
          "The following dates in your selection are unavailable: #{dates_str}. Please adjust your dates or number of guests."
        end
      end
    end
  end

  # Validates all conditions for the booking: availability, booking mode restrictions, guest limits, etc.
  # This should be called whenever dates, guests, or booking mode change to ensure data integrity
  # This is especially important when URL parameters are manipulated by users
  defp validate_all_conditions(
         socket,
         checkin_date,
         checkout_date,
         booking_mode,
         guests_count,
         current_season
       ) do
    # First, check if booking mode is allowed for the selected dates
    {day_booking_allowed, buyout_booking_allowed} =
      allowed_booking_modes(socket.assigns.property, checkin_date, checkout_date, current_season)

    # Validate and normalize guest count (ensure it's within limits)
    guests_count = if guests_count, do: min(max(guests_count, 1), @max_guests), else: 1

    # Validate booking mode is valid
    booking_mode = if booking_mode in [:day, :buyout], do: booking_mode, else: :day

    # Validate dates are in correct order and not in the past
    {checkin_date, checkout_date} =
      if checkin_date && checkout_date do
        today = socket.assigns.today || Date.utc_today()

        # Ensure checkin_date is not in the past
        checkin_date = if Date.compare(checkin_date, today) == :lt, do: today, else: checkin_date

        # Ensure checkout_date is after checkin_date
        checkout_date =
          if Date.compare(checkout_date, checkin_date) != :gt do
            Date.add(checkin_date, 1)
          else
            checkout_date
          end

        {checkin_date, checkout_date}
      else
        {checkin_date, checkout_date}
      end

    # If booking mode is not allowed for the selected dates, set an error
    booking_mode_error =
      cond do
        booking_mode == :day && !day_booking_allowed ->
          "A La Carte bookings are not available for the selected dates based on season settings."

        booking_mode == :buyout && !buyout_booking_allowed ->
          "Full Buyout bookings are not available for the selected dates based on season settings."

        true ->
          nil
      end

    # Validate availability for the selected booking mode and dates
    availability_error =
      if checkin_date && checkout_date && is_nil(booking_mode_error) do
        validate_date_range_for_booking_mode(
          checkin_date,
          checkout_date,
          booking_mode,
          guests_count,
          socket.assigns
        )
      else
        nil
      end

    # Combine errors (booking mode error takes precedence)
    final_error = booking_mode_error || availability_error

    # Update socket with validated values and errors
    socket
    |> assign(
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      guests_count: guests_count,
      selected_booking_mode: booking_mode,
      availability_error: final_error,
      day_booking_allowed: day_booking_allowed,
      buyout_booking_allowed: buyout_booking_allowed
    )
  end

  # Gets active bookings for a user (bookings that haven't ended yet)
  defp get_active_bookings(user_id, limit \\ 10) do
    today = Date.utc_today()

    query =
      from b in Booking,
        where: b.user_id == ^user_id,
        where: b.property == :clear_lake,
        where: b.status == :complete,
        where: b.checkout_date >= ^today,
        order_by: [asc: b.checkin_date],
        limit: ^limit

    Repo.all(query)
  end

  # Determines which booking modes are allowed based on season settings for the selected dates
  # Returns a tuple: {day_booking_allowed, buyout_booking_allowed}
  defp allowed_booking_modes(property, checkin_date, _checkout_date, current_season) do
    case property do
      :clear_lake ->
        # Determine the effective season
        # If dates are selected, use the check-in date's season
        # If not, use the current season (based on today)
        season =
          if checkin_date do
            Bookings.Season.for_date(:clear_lake, checkin_date)
          else
            current_season
          end

        season_id = if season, do: season.id, else: nil

        # Check if pricing rules exist for each mode in this season
        # This ensures we only allow booking modes that have valid pricing configured for the season
        day_pricing_rule =
          Ysc.Bookings.PricingRule.find_most_specific(
            :clear_lake,
            season_id,
            nil,
            nil,
            :day,
            :per_guest_per_day
          )

        buyout_pricing_rule =
          Ysc.Bookings.PricingRule.find_most_specific(
            :clear_lake,
            season_id,
            nil,
            nil,
            :buyout,
            :buyout_fixed
          )

        day_booking_allowed = !is_nil(day_pricing_rule)
        buyout_booking_allowed = !is_nil(buyout_pricing_rule)

        {day_booking_allowed, buyout_booking_allowed}

      _ ->
        # Default: allow both modes
        {true, true}
    end
  end
end
