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
    <div class="py-8 lg:py-10">
      <div class="max-w-screen-xl mx-auto flex flex-col px-4 space-y-6">
        <div class="prose prose-zinc">
          <h1>Clear Lake Cabin</h1>
          <p>
            Select your dates and number of guests to make a reservation at our Clear Lake cabin.
          </p>
        </div>
        <!-- Active Bookings List (Collapsible) -->
        <details
          :if={@user && length(@active_bookings) > 0}
          class="mb-6 bg-teal-50 rounded-lg border-2 border-teal-200 overflow-hidden"
        >
          <summary class="cursor-pointer p-4 hover:bg-teal-100 transition-colors flex items-center justify-between list-none">
            <div class="flex-1">
              <h3 class="text-lg font-semibold text-zinc-900 mb-1">
                Your Active Bookings (<%= length(@active_bookings) %>)
              </h3>
              <% next_booking = List.first(@active_bookings) %>
              <p :if={next_booking} class="text-sm text-zinc-600">
                Next Trip: <%= Calendar.strftime(next_booking.checkin_date, "%b %d") %> at Clear Lake <%= if length(
                                                                                                               @active_bookings
                                                                                                             ) >
                                                                                                               1 do
                  "(#{length(@active_bookings)} bookings)"
                else
                  ""
                end %>
              </p>
            </div>
            <.icon
              name="hero-chevron-down"
              class="w-5 h-5 text-teal-600 chevron-icon flex-shrink-0 ml-4"
            />
          </summary>
          <div class="p-4 pt-0 space-y-3 border-t border-zinc-200">
            <%= for booking <- @active_bookings do %>
              <div class="bg-zinc-50 rounded-md p-3 border border-zinc-200">
                <div class="flex items-start justify-between">
                  <div class="flex-1">
                    <div class="flex items-center gap-2 mb-1 pb-1">
                      <.link
                        navigate={~p"/bookings/#{booking.id}/receipt"}
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
                      navigate={~p"/bookings/#{booking.id}/receipt"}
                      class="text-blue-600 hover:text-blue-800 text-xs font-medium"
                    >
                      View Details →
                    </.link>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </details>
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
            "min-h-[600px]",
            if(!@can_book, do: "relative opacity-60", else: "")
          ]}
        >
          <div
            :if={!@can_book}
            class="absolute inset-0 bg-white bg-opacity-50 rounded-lg pointer-events-none z-10"
          >
          </div>
          <!-- Two-Column Layout -->
          <div class="grid grid-cols-1 lg:grid-cols-3 gap-8 items-start pb-24 lg:pb-0">
            <!-- Left Column: Selection Area (2 columns on large screens) -->
            <div class="lg:col-span-2 space-y-8">
              <!-- Section 1: Booking Type -->
              <section class="bg-zinc-50 p-6 rounded-2xl border border-zinc-200">
                <h2 class="text-lg font-bold mb-4 flex items-center gap-2">
                  <span class="w-6 h-6 bg-teal-600 text-white rounded-full flex items-center justify-center text-xs font-semibold">
                    1
                  </span>
                  Booking Type
                </h2>
                <form phx-change="booking-mode-changed">
                  <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <label class={[
                      "p-4 bg-white border-2 rounded-xl cursor-pointer shadow-sm transition-all",
                      if(@selected_booking_mode == :day && @day_booking_allowed,
                        do: "border-teal-600 bg-teal-50",
                        else: "border-zinc-200 hover:border-zinc-300"
                      ),
                      if(!@day_booking_allowed, do: "opacity-50 cursor-not-allowed", else: "")
                    ]}>
                      <input
                        type="radio"
                        id="booking-mode-day"
                        name="booking_mode"
                        value="day"
                        checked={@selected_booking_mode == :day}
                        disabled={!@day_booking_allowed}
                        class="sr-only"
                      />
                      <div class="flex items-start gap-3">
                        <.icon
                          name="hero-user"
                          class={[
                            "w-6 h-6 flex-shrink-0 mt-0.5",
                            if(@selected_booking_mode == :day && @day_booking_allowed,
                              do: "text-teal-600",
                              else: "text-zinc-500"
                            )
                          ]}
                        />
                        <div class="flex-1">
                          <p class={[
                            "font-bold text-zinc-900 mb-1",
                            if(@selected_booking_mode == :day && @day_booking_allowed,
                              do: "text-teal-900",
                              else: ""
                            )
                          ]}>
                            A La Carte
                          </p>
                          <p class="text-xs text-zinc-500">
                            Shared cabin stay. Perfect for individuals and small groups.
                          </p>
                        </div>
                      </div>
                    </label>
                    <label class={[
                      "p-4 bg-white border-2 rounded-xl cursor-pointer shadow-sm transition-all",
                      if(
                        @selected_booking_mode == :buyout && @buyout_booking_allowed &&
                          is_nil(@availability_error),
                        do: "border-teal-600 bg-teal-50",
                        else: "border-zinc-200 hover:border-zinc-300"
                      ),
                      if(
                        !@buyout_booking_allowed ||
                          (@selected_booking_mode == :buyout && @availability_error),
                        do: "opacity-50 cursor-not-allowed",
                        else: ""
                      )
                    ]}>
                      <input
                        type="radio"
                        id="booking-mode-buyout"
                        name="booking_mode"
                        value="buyout"
                        checked={@selected_booking_mode == :buyout}
                        disabled={
                          !@buyout_booking_allowed ||
                            (@selected_booking_mode == :buyout && @availability_error)
                        }
                        class="sr-only"
                      />
                      <div class="flex items-start gap-3">
                        <.icon
                          name="hero-home-modern"
                          class={[
                            "w-6 h-6 flex-shrink-0 mt-0.5",
                            if(
                              @selected_booking_mode == :buyout && @buyout_booking_allowed &&
                                is_nil(@availability_error),
                              do: "text-teal-600",
                              else: "text-zinc-500"
                            )
                          ]}
                        />
                        <div class="flex-1">
                          <p class={[
                            "font-bold text-zinc-900 mb-1",
                            if(
                              @selected_booking_mode == :buyout && @buyout_booking_allowed &&
                                is_nil(@availability_error),
                              do: "text-teal-900",
                              else: ""
                            )
                          ]}>
                            Full Buyout
                          </p>
                          <p class="text-xs text-zinc-500">
                            Exclusive use of the property. Great for large families.
                          </p>
                          <p
                            :if={
                              @selected_booking_mode == :buyout && @availability_error &&
                                @checkin_date && @checkout_date
                            }
                            class="text-xs text-amber-600 font-medium mt-2"
                          >
                            Buyout unavailable: Other members have already booked spots on these dates.
                          </p>
                        </div>
                      </div>
                    </label>
                  </div>
                </form>
                <div class="mt-4">
                  <p class="text-sm text-zinc-600">
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
                      :if={
                        !@buyout_booking_allowed && @selected_booking_mode == :buyout && @checkin_date
                      }
                      class="text-amber-600 font-medium"
                    >
                      Full Buyout bookings are not available for the selected dates based on season settings.
                    </span>
                  </p>
                </div>
              </section>
              <!-- Section 2: Select Your Dates -->
              <section class="bg-white rounded-2xl border border-zinc-200 overflow-hidden shadow-sm">
                <div class="p-6 border-b border-zinc-100 bg-zinc-50 flex items-center justify-between">
                  <h2 class="text-lg font-bold text-zinc-900 flex items-center gap-2">
                    <span class="w-6 h-6 bg-teal-600 text-white rounded-full flex items-center justify-center text-xs font-semibold">
                      2
                    </span>
                    Select Your Dates
                  </h2>
                  <button
                    :if={@checkin_date || @checkout_date}
                    type="button"
                    phx-click="reset-dates"
                    class="text-xs font-semibold text-teal-600 hover:text-teal-800 transition-colors"
                  >
                    Reset Dates
                  </button>
                </div>
                <div class="p-6">
                  <div class="mb-4">
                    <p class="text-sm font-medium text-zinc-800 mb-2">
                      <span :if={@selected_booking_mode == :day}>
                        The calendar shows how many spots are available for each day (up to 12 guests per day).
                      </span>
                      <span :if={@selected_booking_mode == :buyout}>
                        The calendar shows which dates are available for exclusive full cabin rental.
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
                  <!-- Error Messages -->
                  <div class="mt-4 space-y-1">
                    <p :if={@form_errors[:checkin_date]} class="text-red-600 text-sm">
                      <%= @form_errors[:checkin_date] %>
                    </p>
                    <p :if={@form_errors[:checkout_date]} class="text-red-600 text-sm">
                      <%= @form_errors[:checkout_date] %>
                    </p>
                    <p :if={@date_validation_errors[:weekend]} class="text-red-600 text-sm">
                      <%= @date_validation_errors[:weekend] %>
                    </p>
                    <p :if={@date_validation_errors[:max_nights]} class="text-red-600 text-sm">
                      <%= @date_validation_errors[:max_nights] %>
                    </p>
                    <p :if={@date_validation_errors[:active_booking]} class="text-red-600 text-sm">
                      <%= @date_validation_errors[:active_booking] %>
                    </p>
                    <p
                      :if={@date_validation_errors[:advance_booking_limit]}
                      class="text-red-600 text-sm"
                    >
                      <%= @date_validation_errors[:advance_booking_limit] %>
                    </p>
                    <p :if={@date_validation_errors[:season_date_range]} class="text-red-600 text-sm">
                      <%= @date_validation_errors[:season_date_range] %>
                    </p>
                  </div>
                </div>
              </section>
              <!-- Section 3: Number of Guests -->
              <section
                :if={@selected_booking_mode == :day}
                class="bg-white rounded-2xl border border-zinc-200 overflow-hidden shadow-sm"
              >
                <div class="p-6 border-b border-zinc-100 bg-zinc-50">
                  <h2 class="text-lg font-bold text-zinc-900 flex items-center gap-2">
                    <span class="w-6 h-6 bg-teal-600 text-white rounded-full flex items-center justify-center text-xs font-semibold">
                      3
                    </span>
                    Number of Guests
                  </h2>
                </div>
                <div class="p-8">
                  <div class="max-w-xs">
                    <label for="guests_count" class="block text-sm font-semibold text-zinc-700 mb-4">
                      Staying Guests
                    </label>
                    <form phx-change="guests-changed" phx-debounce="300">
                      <div class="flex items-center justify-center gap-4">
                        <button
                          type="button"
                          phx-click="decrease-guests"
                          disabled={@guests_count <= 1}
                          class={[
                            "w-12 h-12 rounded-full border flex items-center justify-center text-2xl transition-colors",
                            if(@guests_count <= 1,
                              do: "border-zinc-200 bg-zinc-100 text-zinc-400 cursor-not-allowed",
                              else:
                                "border-zinc-300 hover:bg-zinc-100 text-zinc-700 hover:border-teal-300"
                            )
                          ]}
                        >
                          <span>−</span>
                        </button>
                        <input
                          type="number"
                          name="guests_count"
                          id="guests_count"
                          min="1"
                          max={@max_guests || 12}
                          step="1"
                          value={@guests_count}
                          readonly
                          class="w-16 text-2xl font-bold text-center border-0 focus:ring-0 bg-transparent"
                        />
                        <button
                          type="button"
                          phx-click="increase-guests"
                          disabled={@guests_count >= (@max_guests || 12)}
                          class={[
                            "w-12 h-12 rounded-full border-2 flex items-center justify-center text-2xl transition-all font-semibold",
                            if(@guests_count >= (@max_guests || 12),
                              do: "border-zinc-200 bg-zinc-100 text-zinc-400 cursor-not-allowed",
                              else:
                                "border-teal-600 bg-teal-600 hover:bg-teal-700 hover:border-teal-700 text-white"
                            )
                          ]}
                        >
                          <span>+</span>
                        </button>
                      </div>
                    </form>
                    <p class="mt-4 text-xs text-zinc-500 leading-relaxed italic">
                      Note: Children 5 and under stay free. Do not include them in the count above.
                    </p>
                    <p :if={@form_errors[:guests_count]} class="text-red-600 text-sm mt-2">
                      <%= @form_errors[:guests_count] %>
                    </p>
                  </div>
                </div>
              </section>
              <!-- Price Error -->
              <div :if={@price_error} class="bg-red-50 border border-red-200 rounded-lg p-4">
                <div class="flex items-start">
                  <div class="flex-shrink-0">
                    <.icon name="hero-exclamation-circle" class="h-5 w-5 text-red-600" />
                  </div>
                  <div class="ml-3">
                    <p class="text-sm text-red-800"><%= @price_error %></p>
                  </div>
                </div>
              </div>
            </div>
            <!-- Right Column: Sticky Reservation Summary (1 column on large screens) -->
            <aside class="lg:sticky lg:top-24 space-y-4">
              <div class="bg-white rounded-2xl border-2 border-zinc-200 shadow-xl overflow-hidden">
                <div class="p-6 border-b border-zinc-100 bg-zinc-50">
                  <h3 class="text-xl font-bold text-zinc-900">Your Reservation</h3>
                </div>

                <div class="p-6 space-y-4">
                  <!-- Dates -->
                  <div :if={@checkin_date && @checkout_date} class="space-y-2">
                    <div class="flex justify-between text-sm">
                      <span class="text-zinc-500 font-medium">Stay</span>
                      <span class="font-semibold text-zinc-900 text-right">
                        <%= Calendar.strftime(@checkin_date, "%b %d") %> — <%= Calendar.strftime(
                          @checkout_date,
                          "%b %d"
                        ) %>
                      </span>
                    </div>
                    <div class="flex justify-between text-sm">
                      <span class="text-zinc-500 font-medium">Nights</span>
                      <span class="font-semibold text-zinc-900">
                        <%= Date.diff(@checkout_date, @checkin_date) %> <%= if Date.diff(
                                                                                 @checkout_date,
                                                                                 @checkin_date
                                                                               ) == 1,
                                                                               do: "night",
                                                                               else: "nights" %>
                      </span>
                    </div>
                  </div>
                  <!-- Guests -->
                  <div
                    :if={@guests_count && @selected_booking_mode == :day}
                    class="flex justify-between text-sm"
                  >
                    <span class="text-zinc-500 font-medium">Guests</span>
                    <span class="font-semibold text-zinc-900">
                      <%= @guests_count %> <%= if @guests_count == 1, do: "guest", else: "guests" %>
                    </span>
                  </div>
                  <!-- Booking Mode -->
                  <div :if={@selected_booking_mode} class="flex justify-between text-sm">
                    <span class="text-zinc-500 font-medium">Booking Type</span>
                    <span class="font-semibold text-zinc-900">
                      <%= if @selected_booking_mode == :day do
                        "A La Carte"
                      else
                        "Full Buyout"
                      end %>
                    </span>
                  </div>
                  <!-- Availability Error Alert -->
                  <div
                    :if={@availability_error}
                    class="bg-amber-50 border border-amber-200 rounded-lg p-3"
                  >
                    <div class="flex items-start gap-2">
                      <div class="flex-shrink-0">
                        <.icon name="hero-exclamation-triangle" class="h-4 w-4 text-amber-600 mt-0.5" />
                      </div>
                      <div class="flex-1">
                        <h4 class="text-xs font-semibold text-amber-800 mb-1">Availability Issue</h4>
                        <p class="text-xs text-amber-700 leading-relaxed">
                          <%= @availability_error %>
                        </p>
                      </div>
                    </div>
                  </div>
                  <!-- Price Display -->
                  <div
                    :if={@calculated_price && @checkin_date && @checkout_date}
                    class="pt-4 border-t border-zinc-200"
                  >
                    <div class="space-y-3">
                      <!-- Price Breakdown -->
                      <div class="space-y-2 text-sm">
                        <span :if={@selected_booking_mode == :day}>
                          <% nights = Date.diff(@checkout_date, @checkin_date) %>
                          <% price_per_guest_per_night = Money.new(50, :USD) %>
                          <% total_guest_nights = nights * @guests_count %>
                          <div class="flex justify-between items-center text-zinc-600">
                            <span>
                              Spot Rental (<%= @guests_count %> × <%= nights %> night<%= if nights !=
                                                                                              1,
                                                                                            do: "s",
                                                                                            else: "" %>)
                            </span>
                            <span class="font-bold text-zinc-900">
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
                          <div class="flex justify-between items-center text-zinc-600">
                            <span>
                              Full Buyout (<%= nights %> night<%= if nights != 1, do: "s", else: "" %>)
                            </span>
                            <span class="font-bold text-zinc-900">
                              <%= MoneyHelper.format_money!(
                                Money.mult(price_per_night, nights)
                                |> elem(1)
                              ) %>
                            </span>
                          </div>
                        </span>
                      </div>
                      <!-- Total Price -->
                      <div class="flex justify-between items-center pt-4 border-t border-zinc-200">
                        <span class="text-lg font-bold text-zinc-900">Total</span>
                        <span :if={!@availability_error} class="text-3xl font-black text-teal-600">
                          <%= MoneyHelper.format_money!(@calculated_price) %>
                        </span>
                        <span :if={@availability_error} class="text-2xl font-bold text-zinc-400">
                          —
                        </span>
                      </div>
                    </div>
                  </div>
                  <!-- Empty State -->
                  <div :if={!@checkin_date || !@checkout_date} class="text-center py-8">
                    <p class="text-sm text-zinc-500">
                      Select dates to see your reservation summary
                    </p>
                  </div>
                  <!-- Submit Button -->
                  <div :if={@checkin_date && @checkout_date}>
                    <button
                      :if={
                        @can_book &&
                          can_submit_booking?(
                            @selected_booking_mode,
                            @checkin_date,
                            @checkout_date,
                            @guests_count,
                            @availability_error
                          ) &&
                          !@availability_error
                      }
                      phx-click="create-booking"
                      class="w-full bg-teal-600 text-white py-4 rounded-xl font-bold text-lg hover:bg-teal-700 transition-all shadow-lg shadow-teal-100"
                    >
                      Continue to Payment
                    </button>
                    <button
                      :if={@availability_error}
                      type="button"
                      id="update-selection-btn"
                      phx-hook="BackToTop"
                      class="w-full bg-amber-500 text-white py-4 rounded-xl font-bold text-lg hover:bg-amber-600 transition-all shadow-lg shadow-amber-100"
                    >
                      Update Selection
                    </button>
                    <div
                      :if={!@can_book}
                      class="w-full bg-zinc-300 text-zinc-600 font-semibold py-4 rounded-xl text-center cursor-not-allowed"
                    >
                      Booking Unavailable
                    </div>
                  </div>
                </div>
              </div>
              <!-- Capacity Note -->
              <div class="text-center px-4">
                <p class="text-xs text-zinc-400 leading-relaxed">
                  The Clear Lake property has a maximum capacity of <%= @max_guests %> guests per night.
                </p>
              </div>
            </aside>
          </div>
        </div>
        <!-- Information Tab Content -->
        <div :if={@active_tab == :information} class="px-4 lg:px-0">
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
            /* Print-friendly styles */
            @media print {
              details {
                border: 1px solid #ccc !important;
                page-break-inside: avoid;
              }
              details[open] {
                display: block !important;
              }
              details summary {
                display: block !important;
                cursor: default !important;
              }
              .image-carousel-container,
              .sticky-nav,
              button,
              a[href^="http"]:after {
                display: none !important;
              }
              .lg\\:col-span-2 {
                grid-column: span 2;
              }
            }
          </style>
          <!-- Sticky Jump-to Navigation -->
          <div class="hidden lg:block fixed right-8 top-1/2 -translate-y-1/2 z-10">
            <div
              id="info-nav"
              class="bg-white border border-zinc-200 rounded-xl shadow-lg p-4"
              phx-hook="InfoNav"
            >
              <p class="text-xs font-semibold text-zinc-500 uppercase mb-3">Jump to</p>
              <nav class="space-y-2">
                <a
                  href="#arrival-section"
                  data-nav="arrival-section"
                  class="block text-sm text-teal-600 hover:text-teal-700 hover:underline nav-link transition-colors duration-200"
                >
                  Arrival
                </a>
                <a
                  href="#the-stay-section"
                  data-nav="the-stay-section"
                  class="block text-sm text-teal-600 hover:text-teal-700 hover:underline nav-link transition-colors duration-200"
                >
                  The Stay
                </a>
                <a
                  href="#club-standards-section"
                  data-nav="club-standards-section"
                  class="block text-sm text-teal-600 hover:text-teal-700 hover:underline nav-link transition-colors duration-200"
                >
                  Club Standards
                </a>
                <div class="ml-4 mt-2 space-y-1 border-l-2 border-zinc-200 pl-3">
                  <a
                    href="#boating-section"
                    data-nav="boating-section"
                    class="block text-xs text-zinc-500 hover:text-teal-600 hover:underline nav-link transition-colors duration-200"
                  >
                    Boating
                  </a>
                  <a
                    href="#quiet-hours-section"
                    data-nav="quiet-hours-section"
                    class="block text-xs text-zinc-500 hover:text-teal-600 hover:underline nav-link transition-colors duration-200"
                  >
                    Quiet Hours
                  </a>
                  <a
                    href="#pets-section"
                    data-nav="pets-section"
                    class="block text-xs text-zinc-500 hover:text-teal-600 hover:underline nav-link transition-colors duration-200"
                  >
                    Pets
                  </a>
                  <a
                    href="#facilities-section"
                    data-nav="facilities-section"
                    class="block text-xs text-zinc-500 hover:text-teal-600 hover:underline nav-link transition-colors duration-200"
                  >
                    Facilities
                  </a>
                </div>
              </nav>
            </div>
          </div>
          <!-- Welcome Header -->
          <div class="mb-8 prose prose-zinc max-w-none">
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

            <div class="my-8">
              <div class="relative">
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
                <!-- Caption overlay for carousel - positioned inside carousel wrapper -->
                <div class="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/70 via-black/50 to-transparent px-6 py-4 pointer-events-none rounded-b-lg z-10">
                  <p class="text-white text-sm font-medium">
                    Clear Lake Cabin - View from the dock and shared spaces
                  </p>
                </div>
              </div>
              <p class="text-xs text-zinc-500 mt-2 text-center">
                Have a great photo from your stay? Email it to the Marketing Master to be featured here!
              </p>
            </div>
          </div>
          <!-- Essential Prep Row -->
          <section class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-12">
            <div class="bg-teal-900 text-white p-6 rounded-2xl shadow-lg">
              <h3 class="font-bold flex items-center gap-2 mb-4">
                <.icon name="hero-shopping-bag" class="w-5 h-5" /> Packing Checklist
              </h3>
              <ul class="text-sm space-y-2 text-teal-100">
                <li>• Sleeping bag & Pillow</li>
                <li>• Sunscreen & Flip-flops</li>
                <li>• Cooler with ice/beverages</li>
                <li>• <strong>Linens (Not provided)</strong></li>
                <li>• Towel & Swimsuit</li>
                <li class="text-teal-300 text-xs mt-3 italic">💡 Member Tip: Bring earplugs!</li>
              </ul>
            </div>
            <div class="bg-zinc-900 text-white p-6 rounded-2xl shadow-lg">
              <h3 class="font-bold flex items-center gap-2 mb-4">
                <.icon name="hero-truck" class="w-5 h-5" /> Parking Rule
              </h3>
              <p class="text-sm text-zinc-300 leading-relaxed">
                Park based on departure time. If leaving early Sunday, don't get blocked in!
              </p>
              <p class="text-xs text-zinc-400 mt-3">
                Park close to neighbors and align based on your Sunday departure time.
              </p>
            </div>
            <div class="bg-blue-600 text-white p-6 rounded-2xl shadow-lg">
              <h3 class="font-bold flex items-center gap-2 mb-4">
                <.icon name="hero-sparkles" class="w-5 h-5" /> Your Chore
              </h3>
              <p class="text-sm text-blue-50 leading-relaxed">
                Every member signs up for one community chore upon arrival. Check the board in the kitchen.
              </p>
            </div>
          </section>
          <!-- Main Content Grid -->
          <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
            <!-- Left Column: Main Content (2 columns on large screens) -->
            <div class="lg:col-span-2 space-y-12">
              <!-- Arrival Section -->
              <section id="arrival-section">
                <h2 class="text-2xl font-bold text-zinc-900 mb-6">Arrival</h2>
                <div class="space-y-4">
                  <div class="p-6 bg-zinc-50 border border-zinc-200 rounded-2xl flex items-center justify-between">
                    <div>
                      <h3 class="text-xs font-bold text-zinc-400 uppercase tracking-widest mb-1">
                        Cabin Address
                      </h3>
                      <p class="text-lg font-bold text-zinc-900">
                        9325 Bass Road, Kelseyville, CA 95451
                      </p>
                    </div>
                    <a
                      href="https://www.google.com/maps/dir/?api=1&destination=9325+Bass+Road+Kelseyville+CA+95451"
                      target="_blank"
                      class="bg-white px-4 py-2 border border-zinc-300 rounded-lg font-bold text-sm hover:bg-zinc-100 transition-all flex items-center gap-2 whitespace-nowrap"
                    >
                      <.icon name="hero-map-pin" class="w-4 h-4" /> Open in Maps
                    </a>
                  </div>
                  <details class="group border border-zinc-200 rounded-xl overflow-hidden">
                    <summary class="p-4 cursor-pointer font-bold text-zinc-700 flex justify-between items-center list-none bg-zinc-50 hover:bg-zinc-100 transition-colors">
                      Step-by-Step Directions from San Francisco
                      <.icon
                        name="hero-chevron-down"
                        class="w-5 h-5 text-zinc-500 chevron-icon flex-shrink-0"
                      />
                    </summary>
                    <div class="p-4 border-t border-zinc-100 bg-white">
                      <p class="text-sm text-zinc-600 mb-4">
                        Public transportation options are very limited — <strong>driving is essential</strong>.
                      </p>
                      <div class="flex flex-col items-center my-6">
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
                      <!-- Vertical Trail Directions -->
                      <div class="relative pl-8 space-y-6 mt-6">
                        <!-- Trail line -->
                        <div class="absolute left-3 top-0 bottom-0 w-0.5 bg-teal-300"></div>
                        <!-- Direction steps -->
                        <div class="relative flex gap-4">
                          <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-md flex items-center justify-center z-10">
                            <span class="text-white text-xs font-bold">1</span>
                          </div>
                          <div class="flex-1 pb-6">
                            <p class="text-sm font-semibold text-zinc-900">Take HWY 101 North</p>
                            <p class="text-xs text-zinc-600 mt-1">Past Santa Rosa</p>
                          </div>
                        </div>
                        <div class="relative flex gap-4">
                          <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-md flex items-center justify-center z-10">
                            <span class="text-white text-xs font-bold">2</span>
                          </div>
                          <div class="flex-1 pb-6">
                            <p class="text-sm font-semibold text-zinc-900">
                              Exit at River Road / Guerneville
                            </p>
                            <p class="text-xs text-zinc-600 mt-1">Exit 494</p>
                          </div>
                        </div>
                        <div class="relative flex gap-4">
                          <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-md flex items-center justify-center z-10">
                            <span class="text-white text-xs font-bold">3</span>
                          </div>
                          <div class="flex-1 pb-6">
                            <p class="text-sm font-semibold text-zinc-900">
                              Turn right onto Mark West Springs Rd
                            </p>
                            <p class="text-xs text-zinc-600 mt-1">
                              Becomes Porter Creek Rd — go 10.5 miles until it ends
                            </p>
                          </div>
                        </div>
                        <div class="relative flex gap-4">
                          <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-md flex items-center justify-center z-10">
                            <span class="text-white text-xs font-bold">4</span>
                          </div>
                          <div class="flex-1 pb-6">
                            <p class="text-sm font-semibold text-zinc-900">
                              Turn left at stop sign onto Petrified Forest Rd
                            </p>
                            <p class="text-xs text-zinc-600 mt-1">
                              Toward Calistoga — continue 4.6 miles
                            </p>
                          </div>
                        </div>
                        <div class="relative flex gap-4">
                          <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-md flex items-center justify-center z-10">
                            <span class="text-white text-xs font-bold">5</span>
                          </div>
                          <div class="flex-1 pb-6">
                            <p class="text-sm font-semibold text-zinc-900">
                              Turn left at stop sign onto Foothill Blvd / HWY 128
                            </p>
                            <p class="text-xs text-zinc-600 mt-1">Go 0.8 miles</p>
                          </div>
                        </div>
                        <div class="relative flex gap-4">
                          <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-md flex items-center justify-center z-10">
                            <span class="text-white text-xs font-bold">6</span>
                          </div>
                          <div class="flex-1 pb-6">
                            <p class="text-sm font-semibold text-zinc-900">
                              Turn right onto Tubbs Lane
                            </p>
                            <p class="text-xs text-zinc-600 mt-1">Go 1.3 miles to the end</p>
                          </div>
                        </div>
                        <div class="relative flex gap-4">
                          <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-md flex items-center justify-center z-10">
                            <span class="text-white text-xs font-bold">7</span>
                          </div>
                          <div class="flex-1 pb-6">
                            <p class="text-sm font-semibold text-zinc-900">Turn left onto HWY 29</p>
                            <p class="text-xs text-zinc-600 mt-1">
                              Go 28 miles over Mt. St. Helena through Middletown to Lower Lake
                            </p>
                          </div>
                        </div>
                        <div class="relative flex gap-4">
                          <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-md flex items-center justify-center z-10">
                            <span class="text-white text-xs font-bold">8</span>
                          </div>
                          <div class="flex-1 pb-6">
                            <p class="text-sm font-semibold text-zinc-900">
                              Turn left onto HWY 29 at Lower Lake
                            </p>
                            <p class="text-xs text-zinc-600 mt-1">
                              Shell Station on left — go 7.5 miles
                            </p>
                          </div>
                        </div>
                        <div class="relative flex gap-4">
                          <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-md flex items-center justify-center z-10">
                            <span class="text-white text-xs font-bold">9</span>
                          </div>
                          <div class="flex-1 pb-6">
                            <p class="text-sm font-semibold text-zinc-900">
                              Turn right onto Soda Bay Road / HWY 281
                            </p>
                            <p class="text-xs text-zinc-600 mt-1">
                              Kits Corner Store on right — go 4.3 miles
                            </p>
                          </div>
                        </div>
                        <div class="relative flex gap-4">
                          <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-600 border-4 border-white shadow-md flex items-center justify-center z-10">
                            <span class="text-white text-xs font-bold">10</span>
                          </div>
                          <div class="flex-1 pb-6">
                            <p class="text-sm font-semibold text-zinc-900">
                              Turn right onto Bass Road
                            </p>
                            <p class="text-xs text-zinc-600 mt-1">
                              Just after Montezuma Way and a church — go 0.3 miles
                            </p>
                          </div>
                        </div>
                        <div class="relative flex gap-4">
                          <div class="flex-shrink-0 w-6 h-6 rounded-full bg-teal-700 border-4 border-white shadow-lg flex items-center justify-center z-10">
                            <.icon name="hero-flag" class="w-4 h-4 text-white" />
                          </div>
                          <div class="flex-1">
                            <p class="text-sm font-bold text-teal-700">
                              Turn right at the third driveway with the YSC sign
                            </p>
                            <p class="text-xs text-zinc-600 mt-1">You've arrived!</p>
                          </div>
                        </div>
                      </div>
                      <div class="mt-4 p-3 bg-amber-50 border border-amber-200 rounded-lg">
                        <p class="text-sm text-amber-800">
                          <strong>Note:</strong>
                          If you reach Konocti Harbor Inn, you've gone too far — turn around.
                        </p>
                      </div>
                    </div>
                  </details>
                </div>
              </section>
              <!-- The Stay Section -->
              <section id="the-stay-section" class="space-y-6">
                <h2 class="text-2xl font-bold text-zinc-900">The Stay</h2>
                <!-- Property Map -->
                <div class="bg-slate-50 border border-slate-200 rounded-2xl p-6">
                  <h3 class="font-bold text-zinc-900 mb-4 flex items-center gap-2">
                    <.icon name="hero-map" class="w-5 h-5 text-teal-600" /> Where to Sleep
                  </h3>
                  <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <div class="space-y-3">
                      <div class="flex items-start gap-3">
                        <div class="flex-shrink-0 w-8 h-8 rounded-full bg-teal-100 border-2 border-teal-600 flex items-center justify-center">
                          <span class="text-teal-700 font-bold text-sm">1</span>
                        </div>
                        <div>
                          <p class="font-semibold text-zinc-900">Main Lawn</p>
                          <p class="text-sm text-zinc-600">
                            Sleep under the stars — mattresses provided
                          </p>
                        </div>
                      </div>
                      <div class="flex items-start gap-3">
                        <div class="flex-shrink-0 w-8 h-8 rounded-full bg-slate-100 border-2 border-slate-400 flex items-center justify-center">
                          <span class="text-slate-700 font-bold text-sm">2</span>
                        </div>
                        <div>
                          <p class="font-semibold text-zinc-900">Back Lawn</p>
                          <p class="text-sm text-zinc-600">Pitch a small tent (space is limited)</p>
                        </div>
                      </div>
                      <div class="flex items-start gap-3">
                        <div class="flex-shrink-0 w-8 h-8 rounded-full bg-zinc-100 border-2 border-zinc-400 flex items-center justify-center">
                          <.icon name="hero-home" class="w-4 h-4 text-zinc-600" />
                        </div>
                        <div>
                          <p class="font-semibold text-zinc-900">Cabin</p>
                          <p class="text-sm text-zinc-600">Kitchen, bathrooms, and shared spaces</p>
                        </div>
                      </div>
                    </div>
                    <div class="bg-white border border-slate-200 rounded-lg p-4 flex items-center justify-center">
                      <div class="text-center text-zinc-400">
                        <p class="text-xs font-semibold mb-2">Property Layout</p>
                        <div class="text-4xl">🏕️</div>
                        <p class="text-xs mt-2">Main Lawn → Back Lawn → Cabin</p>
                      </div>
                    </div>
                  </div>
                </div>
                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div class="p-5 border border-slate-200 rounded-2xl hover:bg-slate-50 transition-colors bg-slate-50/50">
                    <span class="text-2xl mb-2 block">💧</span>
                    <h4 class="font-bold text-zinc-900 mb-2">Safe Drinking Water</h4>
                    <p class="text-sm text-zinc-600">
                      Tap water is safe. Pro-tip: bring a cooler for ice as stores are 5 miles away.
                    </p>
                  </div>
                  <div class="p-5 border border-slate-200 rounded-2xl hover:bg-slate-50 transition-colors bg-slate-50/50">
                    <span class="text-2xl mb-2 block">🌙</span>
                    <h4 class="font-bold text-zinc-900 mb-2">Quiet Hours</h4>
                    <p class="text-sm text-zinc-600">
                      All lights and music off by midnight (waived for special party weekends).
                    </p>
                  </div>
                </div>
              </section>
              <!-- Club Standards Section -->
              <section id="club-standards-section" class="space-y-4">
                <h2 class="text-2xl font-bold text-zinc-900">Club Standards</h2>
                <!-- Boating (Collapsible) -->
                <details
                  class="group border border-zinc-200 rounded-xl bg-white transition-all"
                  id="boating-section"
                >
                  <summary class="p-4 cursor-pointer font-bold flex justify-between items-center list-none hover:bg-zinc-50">
                    <span class="flex items-center gap-3">
                      <span class="text-xl">🛶</span>
                      <span>Boating & Water</span>
                    </span>
                    <.icon
                      name="hero-chevron-down"
                      class="w-4 h-4 text-zinc-500 chevron-icon transition-transform"
                    />
                  </summary>
                  <div class="px-4 pb-4 text-sm text-zinc-600 leading-relaxed border-t border-zinc-50 pt-4">
                    <p>
                      Private boats are welcome with no mooring fee. Please notify the Cabin Master in advance.
                    </p>
                    <p class="mt-2">
                      Boat trailers <strong>cannot be parked</strong> on YSC grounds.
                    </p>
                    <div class="mt-3 p-3 bg-rose-50 text-rose-700 rounded-lg text-xs border border-rose-200">
                      <strong>⚠️ Important:</strong>
                      Fines of $1,000 apply for Mussel Program non-compliance.
                    </div>
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
                        Please <strong>notify the Cabin Master in advance</strong>
                        so space can be arranged.
                      </li>
                      <li>
                        Boat trailers <strong>cannot be parked</strong> on YSC grounds.
                      </li>
                    </ul>
                    <p class="mt-4">
                      All boats must comply with the
                      <strong>Invasive Mussel Prevention Program</strong>
                      — fines up to <strong>$1,000</strong>
                      apply for non-compliance.
                    </p>
                  </div>
                </details>
                <details
                  class="group border border-zinc-200 rounded-xl bg-white transition-all"
                  id="quiet-hours-section"
                >
                  <summary class="p-4 cursor-pointer font-bold flex justify-between items-center list-none hover:bg-zinc-50">
                    <span class="flex items-center gap-3">
                      <span class="text-xl">🌙</span>
                      <span>Quiet Hours</span>
                    </span>
                    <.icon
                      name="hero-chevron-down"
                      class="w-4 h-4 text-zinc-500 chevron-icon transition-transform"
                    />
                  </summary>
                  <div class="px-4 pb-4 text-sm text-zinc-600 leading-relaxed border-t border-zinc-50 pt-4">
                    <p><strong>All lights and music must be turned off by midnight.</strong></p>
                    <p class="mt-2">
                      This rule may be waived for <strong>special party weekends</strong>
                      — see event details for exceptions.
                    </p>
                  </div>
                </details>
                <details
                  class="group border border-zinc-200 rounded-xl bg-white transition-all"
                  id="responsibilities-section"
                >
                  <summary class="p-4 cursor-pointer font-bold flex justify-between items-center list-none hover:bg-zinc-50">
                    <span class="flex items-center gap-3">
                      <span class="text-xl">🧹</span>
                      <span>General Responsibilities</span>
                    </span>
                    <.icon
                      name="hero-chevron-down"
                      class="w-4 h-4 text-zinc-500 chevron-icon transition-transform"
                    />
                  </summary>
                  <div class="px-4 pb-4 text-sm text-zinc-600 leading-relaxed border-t border-zinc-50 pt-4">
                    <p>Everyone helps make each stay a success!</p>
                    <ul class="mt-2 space-y-1">
                      <li>• Upon arrival, all guests must <strong>sign up for a chore</strong>.</li>
                      <li>• Clear Lake events rely on <strong>every member contributing</strong>.</li>
                    </ul>
                  </div>
                </details>
                <details
                  class="group border border-zinc-200 rounded-xl bg-white transition-all"
                  id="code-of-conduct-section"
                >
                  <summary class="p-4 cursor-pointer font-bold flex justify-between items-center list-none hover:bg-zinc-50">
                    <span class="flex items-center gap-3">
                      <span class="text-xl">📜</span>
                      <span>Code of Conduct</span>
                    </span>
                    <.icon
                      name="hero-chevron-down"
                      class="w-4 h-4 text-zinc-500 chevron-icon transition-transform"
                    />
                  </summary>
                  <div class="px-4 pb-4 text-sm text-zinc-600 leading-relaxed border-t border-zinc-50 pt-4">
                    <p>
                      Everyone attending YSC events or visiting club properties should enjoy a <strong>safe, welcoming, and inclusive environment</strong>.
                    </p>
                    <p class="mt-2">
                      Any behavior that is discriminatory, harassing, or threatening is <strong>strictly prohibited</strong>.
                    </p>
                    <p class="mt-3">
                      The <strong>Cabin Master</strong>
                      or <strong>event host</strong>
                      may determine if conduct violates this policy.
                    </p>
                    <div class="mt-4 space-y-2">
                      <a
                        href="https://ysc.org/non-discrimination-code-of-conduct/"
                        target="_blank"
                        class="block text-teal-600 hover:text-teal-700 underline text-sm"
                      >
                        View the YSC Code of Conduct →
                      </a>
                      <a
                        href="https://ysc.org/conduct-violation-report-form/"
                        target="_blank"
                        class="block text-teal-600 hover:text-teal-700 underline text-sm"
                      >
                        Report a Conduct Violation →
                      </a>
                    </div>
                  </div>
                </details>
                <details
                  class="group border border-zinc-200 rounded-xl bg-white transition-all"
                  id="children-section"
                >
                  <summary class="p-4 cursor-pointer font-bold flex justify-between items-center list-none hover:bg-zinc-50">
                    <span class="flex items-center gap-3">
                      <span class="text-xl">👨‍👩‍👧</span>
                      <span>Children</span>
                    </span>
                    <.icon
                      name="hero-chevron-down"
                      class="w-4 h-4 text-zinc-500 chevron-icon transition-transform"
                    />
                  </summary>
                  <div class="px-4 pb-4 text-sm text-zinc-600 leading-relaxed border-t border-zinc-50 pt-4">
                    <p>
                      Clear Lake is <strong>family-friendly</strong>
                      and ideal for children on most weekends.
                    </p>
                    <p class="mt-2">
                      However, <strong>some party weekends may not be suitable</strong>
                      for kids — refer to event descriptions for guidance.
                    </p>
                  </div>
                </details>
                <details
                  class="group border border-zinc-200 rounded-xl bg-white transition-all"
                  id="pets-section"
                >
                  <summary class="p-4 cursor-pointer font-bold flex justify-between items-center list-none hover:bg-zinc-50">
                    <span class="flex items-center gap-3">
                      <span class="text-xl">🐾</span>
                      <span>Pets</span>
                    </span>
                    <.icon
                      name="hero-chevron-down"
                      class="w-4 h-4 text-zinc-500 chevron-icon transition-transform"
                    />
                  </summary>
                  <div class="px-4 pb-4 text-sm text-zinc-600 leading-relaxed border-t border-zinc-50 pt-4">
                    <p>
                      Dogs and other pets are <strong>not allowed</strong>
                      anywhere on YSC properties, including the <strong>Clear Lake campground</strong>.
                    </p>
                  </div>
                </details>
                <details
                  class="group border border-zinc-200 rounded-xl bg-white transition-all"
                  id="guests-section"
                >
                  <summary class="p-4 cursor-pointer font-bold flex justify-between items-center list-none hover:bg-zinc-50">
                    <span class="flex items-center gap-3">
                      <span class="text-xl">🧍‍♂️</span>
                      <span>Non-Member Guests</span>
                    </span>
                    <.icon
                      name="hero-chevron-down"
                      class="w-4 h-4 text-zinc-500 chevron-icon transition-transform"
                    />
                  </summary>
                  <div class="px-4 pb-4 text-sm text-zinc-600 leading-relaxed border-t border-zinc-50 pt-4">
                    <p>Guests are welcome on general visits, but:</p>
                    <ul class="mt-2 space-y-1">
                      <li>
                        • All guests must be <strong>included in and paid for</strong>
                        by the member making the reservation.
                      </li>
                      <li>
                        • Certain events may have <strong>guest restrictions</strong>
                        — check event details for specifics.
                      </li>
                    </ul>
                  </div>
                </details>
                <details
                  class="group border border-zinc-200 rounded-xl bg-white transition-all"
                  id="facilities-section"
                >
                  <summary class="p-4 cursor-pointer font-bold flex justify-between items-center list-none hover:bg-zinc-50">
                    <span class="flex items-center gap-3">
                      <span class="text-xl">🏡</span>
                      <span>Cabin Facilities</span>
                    </span>
                    <.icon
                      name="hero-chevron-down"
                      class="w-4 h-4 text-zinc-500 chevron-icon transition-transform"
                    />
                  </summary>
                  <div class="px-4 pb-4 text-sm text-zinc-600 leading-relaxed border-t border-zinc-50 pt-4">
                    <p>The Clear Lake cabin includes:</p>
                    <ul class="mt-2 space-y-1">
                      <li>• A large <strong>kitchen</strong></li>
                      <li>• <strong>Men's and women's bathrooms</strong> and changing rooms</li>
                      <li>
                        • A <strong>living room / dance floor</strong> for gatherings and events
                      </li>
                    </ul>
                  </div>
                </details>
                <details
                  class="group border border-zinc-200 rounded-xl bg-white transition-all"
                  id="nearby-section"
                >
                  <summary class="p-4 cursor-pointer font-bold flex justify-between items-center list-none hover:bg-zinc-50">
                    <span class="flex items-center gap-3">
                      <span class="text-xl">🌄</span>
                      <span>Things to Do Nearby</span>
                    </span>
                    <.icon
                      name="hero-chevron-down"
                      class="w-4 h-4 text-zinc-500 chevron-icon transition-transform"
                    />
                  </summary>
                  <div class="px-4 pb-4 text-sm text-zinc-600 leading-relaxed border-t border-zinc-50 pt-4">
                    <p>
                      While the cabin offers plenty of on-site fun, consider exploring these local attractions:
                    </p>
                    <ul class="mt-3 space-y-2">
                      <li>
                        <a
                          href="https://lakecounty.com"
                          target="_blank"
                          class="text-teal-600 hover:text-teal-700 underline"
                        >
                          Lake County Tourism Board →
                        </a>
                      </li>
                      <li>
                        <a
                          href="https://www.konoctitrails.com"
                          target="_blank"
                          class="text-teal-600 hover:text-teal-700 underline"
                        >
                          Konocti Trails – Hiking Mount Konocti →
                        </a>
                      </li>
                      <li>
                        <a
                          href="https://www.parks.ca.gov/?page_id=473"
                          target="_blank"
                          class="text-teal-600 hover:text-teal-700 underline"
                        >
                          Clear Lake State Park →
                        </a>
                      </li>
                      <li>
                        <a
                          href="https://lakecountywineries.org"
                          target="_blank"
                          class="text-teal-600 hover:text-teal-700 underline"
                        >
                          Lake County Wine Tasting →
                        </a>
                        <span class="text-zinc-500"> — visit one of a dozen nearby wineries!</span>
                      </li>
                    </ul>
                  </div>
                </details>
              </section>
            </div>
            <!-- Right Sidebar -->
            <aside class="space-y-6">
              <!-- Packing List Card -->
              <div class="bg-teal-900 text-white rounded-3xl p-8 shadow-xl">
                <h3 class="text-lg font-bold mb-4 flex items-center gap-2">
                  <.icon name="hero-shopping-bag" class="w-6 h-6" /> Packing List
                </h3>
                <ul class="space-y-3 text-teal-100 text-sm">
                  <li class="flex items-center gap-3">
                    <.icon name="hero-check-circle" class="w-5 h-5 text-teal-400 flex-shrink-0" />
                    <span>Sleeping bag & Pillow</span>
                  </li>
                  <li class="flex items-center gap-3">
                    <.icon name="hero-check-circle" class="w-5 h-5 text-teal-400 flex-shrink-0" />
                    <span>Towel & Swimsuit</span>
                  </li>
                  <li class="flex items-center gap-3">
                    <.icon name="hero-check-circle" class="w-5 h-5 text-teal-400 flex-shrink-0" />
                    <span>Sunscreen & Flip-flops</span>
                  </li>
                  <li class="flex items-center gap-3">
                    <.icon name="hero-check-circle" class="w-5 h-5 text-teal-400 flex-shrink-0" />
                    <span>Cooler with ice & drinks</span>
                  </li>
                  <li class="flex items-center gap-3">
                    <.icon name="hero-check-circle" class="w-5 h-5 text-teal-400 flex-shrink-0" />
                    <span>Dancing shoes (for events)</span>
                  </li>
                </ul>
                <p class="mt-6 text-[10px] text-teal-300 uppercase tracking-widest font-bold">
                  Member Tip: Bring earplugs!
                </p>
              </div>
              <!-- Logistics At-A-Glance Card -->
              <div class="bg-white border border-zinc-200 rounded-2xl overflow-hidden">
                <div class="p-4 bg-zinc-50 border-b border-zinc-100 font-bold text-sm text-zinc-900">
                  Logistics At-A-Glance
                </div>
                <table class="w-full text-xs">
                  <tr class="border-b border-zinc-50">
                    <td class="p-3 text-zinc-500">Check-in</td>
                    <td class="p-3 font-bold text-right text-zinc-900">3:00 PM</td>
                  </tr>
                  <tr class="border-b border-zinc-50">
                    <td class="p-3 text-zinc-500">Check-out</td>
                    <td class="p-3 font-bold text-right text-zinc-900">11:00 AM</td>
                  </tr>
                  <tr class="border-b border-zinc-50">
                    <td class="p-3 text-zinc-500">Pets</td>
                    <td class="p-3 font-bold text-right text-red-600">Not Allowed</td>
                  </tr>
                  <tr class="border-b border-zinc-50">
                    <td class="p-3 text-zinc-500">Max Capacity</td>
                    <td class="p-3 font-bold text-right text-zinc-900"><%= @max_guests %> guests</td>
                  </tr>
                  <tr>
                    <td class="p-3 text-zinc-500">Children (≤5)</td>
                    <td class="p-3 font-bold text-right text-zinc-900">Free</td>
                  </tr>
                </table>
              </div>
            </aside>
          </div>
          <!-- Footer -->
          <div class="mt-12 pt-8 border-t border-zinc-200 text-center">
            <p class="text-sm text-zinc-600 italic">
              The Clear Lake cabin has been a member-run treasure since 1963. Thank you for doing your part to keep it clean for the next family.
            </p>
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

  def handle_event("increase-guests", _params, socket) do
    current_count = socket.assigns.guests_count || 1
    new_count = min(current_count + 1, @max_guests)

    # Check if the selected dates still have enough spots available
    availability_error =
      if socket.assigns.selected_booking_mode == :day &&
           socket.assigns.checkin_date &&
           socket.assigns.checkout_date do
        validate_guests_against_availability(
          socket.assigns.checkin_date,
          socket.assigns.checkout_date,
          new_count,
          socket.assigns
        )
      else
        nil
      end

    socket =
      socket
      |> assign(
        guests_count: new_count,
        calculated_price: nil,
        price_error: nil,
        availability_error: availability_error
      )
      |> calculate_price_if_ready()
      |> then(fn updated_socket ->
        update_url_with_guests(updated_socket)
      end)

    {:noreply, socket}
  end

  def handle_event("decrease-guests", _params, socket) do
    current_count = socket.assigns.guests_count || 1
    new_count = max(current_count - 1, 1)

    # Check if the selected dates still have enough spots available
    availability_error =
      if socket.assigns.selected_booking_mode == :day &&
           socket.assigns.checkin_date &&
           socket.assigns.checkout_date do
        validate_guests_against_availability(
          socket.assigns.checkin_date,
          socket.assigns.checkout_date,
          new_count,
          socket.assigns
        )
      else
        nil
      end

    socket =
      socket
      |> assign(
        guests_count: new_count,
        calculated_price: nil,
        price_error: nil,
        availability_error: availability_error
      )
      |> calculate_price_if_ready()
      |> then(fn updated_socket ->
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
