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
    <!-- Booking Dashboard Section -->
    <section :if={@user} class="bg-zinc-50 border-b border-zinc-200 py-12">
      <div class="max-w-screen-xl mx-auto px-4 space-y-10">
        <!-- Dashboard Header -->
        <div class="flex flex-col md:flex-row md:items-end justify-between gap-4 border-b border-zinc-200 pb-6">
          <div>
            <h1 class="text-3xl font-bold text-zinc-900">Member Portal: Clear Lake</h1>
            <p class="text-zinc-500">Manage your stays and reserve new dates below.</p>
          </div>
        </div>
        <!-- Active Bookings -->
        <div :if={length(@active_bookings) > 0} class="space-y-4">
          <h3 class="text-sm font-bold text-zinc-400 uppercase tracking-widest">Upcoming Trips</h3>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            <%= for booking <- @active_bookings do %>
              <div class="bg-white border-2 border-teal-100 rounded-xl p-5 shadow-sm">
                <div class="flex justify-between items-start mb-3">
                  <span class="text-[10px] font-bold text-teal-600 bg-teal-50 px-2 py-0.5 rounded">
                    <%= booking.reference_id %>
                  </span>
                  <%= if Date.compare(booking.checkout_date, Date.utc_today()) == :eq do %>
                    <span class="text-xs font-bold text-amber-600 italic">Today!</span>
                  <% else %>
                    <span class="text-xs font-bold text-green-600 italic">Active</span>
                  <% end %>
                </div>
                <p class="font-bold text-zinc-900 text-lg leading-none">
                  <%= Calendar.strftime(booking.checkin_date, "%b %d") %> — <%= Calendar.strftime(
                    booking.checkout_date,
                    "%b %d"
                  ) %>
                </p>
                <p class="text-sm text-zinc-500 mt-1">
                  <%= booking.guests_count %> <%= if booking.guests_count == 1,
                    do: "Guest",
                    else: "Guests" %> • <%= if booking.booking_mode == :buyout,
                    do: "Full Buyout",
                    else: "Shared Stay" %>
                </p>
                <.link
                  navigate={~p"/bookings/#{booking.id}/receipt"}
                  class="inline-block mt-4 text-sm font-semibold text-teal-600 hover:underline"
                >
                  View Booking →
                </.link>
              </div>
            <% end %>
          </div>
        </div>
        <!-- Booking Form -->
        <div :if={@can_book} class="grid grid-cols-1 lg:grid-cols-3 gap-8 items-start">
          <!-- Left Column: Selection Area (2 columns on large screens) -->
          <div class="lg:col-span-2 space-y-6">
            <div class="bg-white rounded-2xl border border-zinc-200 shadow-sm overflow-hidden">
              <div class="bg-zinc-900 p-4 text-white flex justify-between items-center">
                <span class="text-sm font-bold">New Reservation</span>
                <span class="text-xs text-zinc-400 font-light">
                  Max capacity: <%= @max_guests %> guests
                </span>
              </div>
              <div class="p-6 space-y-6">
                <!-- Section 1: Booking Type -->
                <section class="bg-zinc-50 p-6 rounded border border-zinc-200">
                  <h2 class="text-lg font-bold mb-4 flex items-center gap-2">
                    <span class="w-6 h-6 bg-teal-600 text-white rounded-full flex items-center justify-center text-xs font-semibold">
                      1
                    </span>
                    Booking Type
                  </h2>
                  <form phx-change="booking-mode-changed">
                    <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                      <label class={[
                        "p-4 bg-white border-2 rounded cursor-pointer shadow-sm transition-all",
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
                        "p-4 bg-white border-2 rounded cursor-pointer shadow-sm transition-all",
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
                          !@buyout_booking_allowed && @selected_booking_mode == :buyout &&
                            @checkin_date
                        }
                        class="text-amber-600 font-medium"
                      >
                        Full Buyout bookings are not available for the selected dates based on season settings.
                      </span>
                    </p>
                  </div>
                </section>
                <!-- Section 2: Select Your Dates -->
                <section class="bg-white rounded border border-zinc-200 overflow-hidden shadow-sm">
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
                      <p
                        :if={@date_validation_errors[:season_date_range]}
                        class="text-red-600 text-sm"
                      >
                        <%= @date_validation_errors[:season_date_range] %>
                      </p>
                    </div>
                  </div>
                </section>
                <!-- Section 3: Number of Guests -->
                <section
                  :if={@selected_booking_mode == :day}
                  class="bg-white rounded border border-zinc-200 overflow-hidden shadow-sm"
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
            </div>
          </div>
          <!-- Right Column: Sticky Reservation Summary -->
          <aside class="sticky top-24">
            <div class="bg-white rounded-2xl border-2 border-teal-600 shadow-xl p-6">
              <h3 class="text-xl font-bold text-zinc-900 mb-6">Reservation Details</h3>

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
                  <.button
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
                    class="w-full text-lg py-4"
                    color="teal"
                  >
                    Continue to Payment
                  </.button>
                  <.button
                    :if={@availability_error}
                    type="button"
                    id="update-selection-btn"
                    phx-hook="BackToTop"
                    class="w-full text-lg py-4"
                    color="amber"
                  >
                    Update Selection
                  </.button>
                  <div
                    :if={!@can_book}
                    class="w-full bg-zinc-200 text-zinc-600 font-semibold py-4 rounded text-center cursor-not-allowed"
                  >
                    Booking Unavailable
                  </div>
                </div>
              </div>
            </div>
          </aside>
        </div>
      </div>
    </section>
    <!-- Hero Section with Carousel (Smaller for logged-in users) -->
    <section :if={@user} class="relative h-[30vh] w-full overflow-hidden">
      <div id="clear-lake-carousel-wrapper" phx-hook="ImageCarouselAutoplay" class="absolute inset-0">
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
          class="h-full w-full object-cover"
        />
      </div>
    </section>
    <!-- Hero Section with Carousel (Full size for non-logged-in users) -->
    <section :if={!@user} class="relative h-[60vh] lg:h-[75vh] w-full overflow-hidden">
      <div id="clear-lake-carousel-wrapper" phx-hook="ImageCarouselAutoplay" class="absolute inset-0">
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
          class="h-full w-full object-cover"
        >
          <:overlay>
            <div class="absolute bottom-0 left-0 right-0 z-20 p-8 lg:p-16 max-w-screen-xl mx-auto">
              <span class="inline-block px-3 py-1 mb-4 text-xs font-bold tracking-widest text-white uppercase bg-teal-600 rounded">
                Summer Destination
              </span>
              <h1 class="text-4xl lg:text-7xl font-bold text-white mb-4 drop-shadow-lg">
                Clear Lake Cabin
              </h1>
              <p class="text-lg lg:text-2xl text-zinc-100 max-w-2xl font-light">
                Experience California's largest natural lake from our historic, member-run retreat.
              </p>
            </div>
          </:overlay>
        </YscWeb.Components.ImageCarousel.image_carousel>
      </div>
    </section>
    <!-- Main Content Grid: 2-column layout -->
    <section class="max-w-screen-xl mx-auto px-4 py-20">
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-16">
        <!-- Left Column: Main Content (2 columns on large screens) -->
        <div class="lg:col-span-2 space-y-20">
          <!-- Life at the Cabin Section -->
          <article id="amenities" class="mb-20">
            <h2 class="text-3xl font-bold text-zinc-900 mb-4">Life at the Cabin</h2>
            <p class="text-zinc-500 mb-10">Essential details for a perfect lakeside stay.</p>
            <div class="prose prose-lg prose-zinc font-light leading-relaxed text-zinc-600 max-w-none">
              <p>
                Established in 1963, the Young Scandinavians Club Clear Lake cabin is more than just a rental—it's a shared heritage. Nestled in the heart of Kelseyville, our cabin serves as a sun-drenched sanctuary for members seeking the rustic charm of lakeside living.
              </p>
              <p>
                From <strong>May through September</strong>, the cabin buzzes with community spirit. Whether you're here for a themed party weekend or a quiet escape, the cool waters of the lake and the warmth of shared meals define the experience.
              </p>
            </div>
            <!-- CTA Card for Non-Logged-In Users -->
            <div
              :if={!@can_book}
              class="mt-10 p-8 rounded-2xl bg-teal-50 border border-teal-100 flex flex-col md:flex-row items-center justify-between gap-6"
            >
              <div>
                <h4 class="text-xl font-bold text-teal-900">Ready to reserve?</h4>
                <p class="text-teal-700"><%= raw(@booking_disabled_reason) %></p>
              </div>
              <.link
                navigate={~p"/users/log-in"}
                class="px-8 py-3 bg-teal-600 text-white font-bold rounded-lg hover:bg-teal-700 transition shadow-lg shadow-teal-200"
              >
                Sign In to Book
              </.link>
            </div>
          </article>
          <!-- Arrival Section -->
          <article id="arrival-section" class="pt-10 border-t border-zinc-100">
            <h2 class="text-3xl font-bold text-zinc-900 mb-8">Journey to the Lake</h2>
            <div class="space-y-4">
              <div class="p-6 bg-zinc-50 border border-zinc-200 rounded flex items-center justify-between">
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
                  class="bg-white px-4 py-2 border border-zinc-300 rounded font-bold text-sm hover:bg-zinc-100 transition-all flex items-center gap-2 whitespace-nowrap"
                >
                  <.icon name="hero-map-pin" class="w-4 h-4" /> Open in Maps
                </a>
              </div>
              <details class="group border border-zinc-200 rounded overflow-hidden">
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
          </article>
          <!-- What to Expect Section -->
          <section id="the-stay-section" class="mb-20">
            <h2 class="text-3xl font-bold text-zinc-900 mb-10 text-center lg:text-left">
              What to Expect
            </h2>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-8">
              <div class="flex gap-4">
                <div class="w-12 h-12 flex-shrink-0 bg-zinc-100 rounded-lg flex items-center justify-center">
                  <.icon name="hero-home" class="w-6 h-6 text-teal-600" />
                </div>
                <div>
                  <h4 class="font-bold text-zinc-900 mb-1">Communal Cabin</h4>
                  <p class="text-sm text-zinc-500 leading-relaxed">
                    A fully-equipped group kitchen, changing rooms, and a dance floor for social evenings.
                  </p>
                </div>
              </div>
              <div class="flex gap-4">
                <div class="w-12 h-12 flex-shrink-0 bg-zinc-100 rounded-lg flex items-center justify-center">
                  <.icon name="hero-sparkles" class="w-6 h-6 text-teal-600" />
                </div>
                <div>
                  <h4 class="font-bold text-zinc-900 mb-1">Lawn Sleeping</h4>
                  <p class="text-sm text-zinc-500 leading-relaxed">
                    Embrace the lake breeze. We provide mattresses for sleeping under the stars on the main lawn.
                  </p>
                </div>
              </div>
              <div class="flex gap-4">
                <div class="w-12 h-12 flex-shrink-0 bg-zinc-100 rounded-lg flex items-center justify-center">
                  <.icon name="hero-beaker" class="w-6 h-6 text-teal-600" />
                </div>
                <div>
                  <h4 class="font-bold text-zinc-900 mb-1">Filtered Water</h4>
                  <p class="text-sm text-zinc-500 leading-relaxed">
                    Safe, clean tap water is available. No need to bring plastic flats; just bring a reusable bottle.
                  </p>
                </div>
              </div>
              <div class="flex gap-4">
                <div class="w-12 h-12 flex-shrink-0 bg-zinc-100 rounded-lg flex items-center justify-center">
                  <.icon name="hero-lifebuoy" class="w-6 h-6 text-teal-600" />
                </div>
                <div>
                  <h4 class="font-bold text-zinc-900 mb-1">Private Dock</h4>
                  <p class="text-sm text-zinc-500 leading-relaxed">
                    Perfect for swimming, mooring your boat, or enjoying a morning coffee over the water.
                  </p>
                </div>
              </div>
            </div>
          </section>
          <!-- Club Standards Section -->
          <section id="club-standards-section" class="bg-white rounded-lg p-10 mb-10 shadow-sm">
            <h2 class="text-3xl font-bold text-zinc-900 mb-8">Club Standards</h2>
            <div class="space-y-4">
              <!-- Boating (Collapsible) -->
              <details
                class="group border border-zinc-200 rounded bg-white transition-all"
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
                <div class="px-4 pb-5 text-base text-zinc-700 leading-relaxed border-t border-zinc-50 pt-5 space-y-4">
                  <p>
                    Private boats are welcome with no mooring fee. Please notify the Cabin Master in advance.
                  </p>
                  <p>
                    Boat trailers <strong>cannot be parked</strong> on YSC grounds.
                  </p>
                  <div class="p-4 bg-rose-50 text-rose-700 rounded-lg text-sm border border-rose-200">
                    <strong>⚠️ Important:</strong>
                    Fines of $1,000 apply for Mussel Program non-compliance.
                  </div>
                </div>
              </details>
              <details
                class="group border border-zinc-200 rounded bg-white transition-all"
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
                <div class="px-4 pb-5 text-base text-zinc-700 leading-relaxed border-t border-zinc-50 pt-5 space-y-3">
                  <p>
                    <strong>All lights and music must be turned off by midnight.</strong>
                  </p>
                  <p>
                    This rule may be waived for <strong>special party weekends</strong>
                    — see event details for exceptions.
                  </p>
                </div>
              </details>
              <details
                class="group border border-zinc-200 rounded bg-white transition-all"
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
                <div class="px-4 pb-5 text-base text-zinc-700 leading-relaxed border-t border-zinc-50 pt-5 space-y-3">
                  <p>Everyone helps make each stay a success!</p>
                  <ul class="space-y-2">
                    <li>• Upon arrival, all guests must <strong>sign up for a chore</strong>.</li>
                    <li>
                      • Clear Lake events rely on <strong>every member contributing</strong>.
                    </li>
                  </ul>
                </div>
              </details>
              <details
                class="group border border-zinc-200 rounded bg-white transition-all"
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
                <div class="px-4 pb-5 text-base text-zinc-700 leading-relaxed border-t border-zinc-50 pt-5 space-y-4">
                  <p>
                    Everyone attending YSC events or visiting club properties should enjoy a <strong>safe, welcoming, and inclusive environment</strong>.
                  </p>
                  <p>
                    Any behavior that is discriminatory, harassing, or threatening is <strong>strictly prohibited</strong>.
                  </p>
                  <p>
                    The <strong>Cabin Master</strong>
                    or <strong>event host</strong>
                    may determine if conduct violates this policy.
                  </p>
                  <div class="space-y-2">
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
                class="group border border-zinc-200 rounded bg-white transition-all"
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
                <div class="px-4 pb-5 text-base text-zinc-700 leading-relaxed border-t border-zinc-50 pt-5 space-y-3">
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
              <details
                class="group border border-zinc-200 rounded bg-white transition-all"
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
                <div class="px-4 pb-5 text-base text-zinc-700 leading-relaxed border-t border-zinc-50 pt-5">
                  <p>
                    Dogs and other pets are <strong>not allowed</strong>
                    anywhere on YSC properties, including the <strong>Clear Lake campground</strong>.
                  </p>
                </div>
              </details>
              <details
                class="group border border-zinc-200 rounded bg-white transition-all"
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
                <div class="px-4 pb-5 text-base text-zinc-700 leading-relaxed border-t border-zinc-50 pt-5 space-y-3">
                  <p>Guests are welcome on general visits, but:</p>
                  <ul class="space-y-2">
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
              <!-- Cabin Facilities - Icon Grid -->
              <div id="facilities-section" class="mt-6">
                <h3 class="text-xl font-bold text-zinc-900 mb-4 flex items-center gap-3">
                  <.icon name="hero-home-modern" class="w-6 h-6 text-teal-600" /> Cabin Facilities
                </h3>
                <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                  <div class="bg-zinc-50 border border-zinc-200 rounded-lg p-5 text-center hover:bg-zinc-100 transition-colors">
                    <.icon name="hero-squares-2x2" class="w-8 h-8 text-teal-600 mx-auto mb-3" />
                    <h4 class="font-semibold text-zinc-900 mb-1">Large Kitchen</h4>
                    <p class="text-xs text-zinc-600">Fully equipped for group meals</p>
                  </div>
                  <div class="bg-zinc-50 border border-zinc-200 rounded-lg p-5 text-center hover:bg-zinc-100 transition-colors">
                    <.icon name="hero-user-group" class="w-8 h-8 text-teal-600 mx-auto mb-3" />
                    <h4 class="font-semibold text-zinc-900 mb-1">Bathrooms</h4>
                    <p class="text-xs text-zinc-600">Men's & women's changing rooms</p>
                  </div>
                  <div class="bg-zinc-50 border border-zinc-200 rounded-lg p-5 text-center hover:bg-zinc-100 transition-colors">
                    <.icon name="hero-musical-note" class="w-8 h-8 text-teal-600 mx-auto mb-3" />
                    <h4 class="font-semibold text-zinc-900 mb-1">Living Room</h4>
                    <p class="text-xs text-zinc-600">Dance floor for gatherings</p>
                  </div>
                </div>
              </div>
              <details
                class="group border border-zinc-200 rounded bg-white transition-all"
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
                <div class="px-4 pb-5 text-base text-zinc-700 leading-relaxed border-t border-zinc-50 pt-5 space-y-4">
                  <p>
                    While the cabin offers plenty of on-site fun, consider exploring these local attractions:
                  </p>
                  <ul class="space-y-2">
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
            </div>
          </section>
        </div>
        <!-- Right Sidebar -->
        <aside class="space-y-8">
          <div class="sticky top-24 space-y-8">
            <!-- Quick Logistics Card -->
            <div class="bg-white border-2 border-zinc-100 rounded-2xl overflow-hidden shadow-sm">
              <div class="bg-zinc-50 px-6 py-4 border-b border-zinc-100">
                <h3 class="font-bold text-zinc-900">Quick Logistics</h3>
              </div>
              <div class="p-6 space-y-4">
                <div class="flex justify-between text-sm">
                  <span class="text-zinc-500">Check-in</span>
                  <span class="font-bold">3:00 PM</span>
                </div>
                <div class="flex justify-between text-sm">
                  <span class="text-zinc-500">Check-out</span>
                  <span class="font-bold">11:00 AM</span>
                </div>
                <div class="flex justify-between text-sm border-t border-zinc-50 pt-4">
                  <span class="text-zinc-500">Capacity</span>
                  <span class="font-bold"><%= @max_guests %> Guests</span>
                </div>
                <div class="flex justify-between text-sm">
                  <span class="text-zinc-500">Pets</span>
                  <span class="font-bold text-rose-600">No Dogs Allowed</span>
                </div>
              </div>
            </div>
            <!-- Essential Packing Card - Dark Teal -->
            <div class="bg-teal-900 rounded-2xl p-8 text-white shadow-xl shadow-teal-900/20">
              <h3 class="text-lg font-bold mb-6 flex items-center gap-2">
                <.icon name="hero-shopping-bag" class="w-6 h-6" /> Essential Packing
              </h3>
              <ul class="space-y-4 text-sm text-teal-100">
                <li class="flex gap-3">
                  <span class="text-teal-400">✓</span>
                  <span><strong>Bedding:</strong> Sleeping bag & pillow</span>
                </li>
                <li class="flex gap-3">
                  <span class="text-teal-400">✓</span>
                  <span><strong>Swim Gear:</strong> Towels & sun protection</span>
                </li>
                <li class="flex gap-3">
                  <span class="text-teal-400">✓</span>
                  <span><strong>Cooler:</strong> Ice is 5 miles away, bring plenty</span>
                </li>
                <li class="flex gap-3 border-t border-white/10 pt-4">
                  <span class="text-teal-400">!</span>
                  <span class="italic">
                    Chore duty is required for all guests. Check the kitchen board upon arrival.
                  </span>
                </li>
              </ul>
            </div>
          </div>
        </aside>
      </div>
      <!-- Footer -->
      <div class="mt-12 pt-8 border-t border-zinc-100 text-center">
        <p class="text-sm text-zinc-600 italic">
          The Clear Lake cabin has been a member-run treasure since 1963. Thank you for doing your part to keep it clean for the next family.
        </p>
      </div>
    </section>
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
    case YscWeb.UserAuth.get_membership_plan_type(subscription) do
      nil -> :none
      plan_id -> plan_id
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
