defmodule YscWeb.TahoeBookingLive do
  use YscWeb, :live_view

  alias Ysc.Bookings
  alias Ysc.Bookings.{Season, Booking, PricingRule, Room, BookingLocker, PropertyInventory}
  alias Ysc.Bookings.SeasonHelpers
  alias Ysc.Bookings.PricingHelpers
  alias Ysc.MoneyHelper
  alias Ysc.Accounts
  alias Ysc.Subscriptions
  alias Ysc.Repo
  require Logger
  import Ecto.Query

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user

    today = Date.utc_today()

    # Load seasons once using cache to avoid multiple queries
    alias Ysc.Bookings.SeasonCache
    seasons = SeasonCache.get_all_for_property(:tahoe)

    {current_season, season_start_date, season_end_date} =
      get_current_season_info_cached(seasons, today)

    max_booking_date = calculate_max_booking_date_cached(seasons, today)

    # Parse query parameters, handling malformed/double-encoded URLs
    parsed_params = parse_mount_params(params)

    # Parse dates and guest counts from URL params if present
    {checkin_date, checkout_date} = parse_dates_from_params(parsed_params)
    guests_count = parse_guests_from_params(parsed_params)
    children_count = parse_children_from_params(parsed_params)
    requested_tab = parse_tab_from_params(parsed_params)
    booking_mode = parse_booking_mode_from_params(parsed_params) || :room

    date_form =
      to_form(
        %{
          "checkin_date" => date_to_datetime_string(checkin_date),
          "checkout_date" => date_to_datetime_string(checkout_date)
        },
        as: "booking_dates"
      )

    # Load active bookings for the user first (needed for eligibility check)
    active_bookings = if user, do: get_active_bookings(user.id), else: []

    # Check if user can book (pass active_bookings to avoid duplicate query)
    {can_book, booking_error_title, booking_disabled_reason} =
      check_booking_eligibility(user, active_bookings)

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

    # Calculate restricted date range for family/lifetime members with 1 room booking
    {restricted_min_date, restricted_max_date} =
      if membership_type in [:family, :lifetime] && length(active_bookings) > 0 do
        total_rooms = count_rooms_in_active_bookings(active_bookings)

        if total_rooms == 1 do
          calculate_restricted_date_range(active_bookings, max_booking_date)
        else
          {today, max_booking_date}
        end
      else
        {today, max_booking_date}
      end

    # Check if dates are actually restricted (different from default range)
    dates_restricted =
      dates_are_restricted?(restricted_min_date, restricted_max_date, today, max_booking_date)

    # Load refund policies for both booking modes
    buyout_refund_policy = Bookings.get_active_refund_policy(:tahoe, :buyout)
    room_refund_policy = Bookings.get_active_refund_policy(:tahoe, :room)

    # Generate date tooltips for unavailable dates
    date_tooltips =
      generate_date_tooltips(restricted_min_date, restricted_max_date, today, :tahoe, seasons)

    socket =
      assign(socket,
        page_title: "Tahoe Cabin",
        property: :tahoe,
        user: user_with_subs,
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        today: today,
        max_booking_date: max_booking_date,
        restricted_min_date: restricted_min_date,
        restricted_max_date: restricted_max_date,
        dates_restricted: dates_restricted,
        current_season: current_season,
        season_start_date: season_start_date,
        season_end_date: season_end_date,
        seasons: seasons,
        selected_room_id: nil,
        selected_room_ids: [],
        selected_booking_mode: booking_mode,
        guests_count: guests_count,
        children_count: children_count,
        guests_dropdown_open: false,
        available_rooms: [],
        calculated_price: nil,
        price_breakdown: nil,
        price_error: nil,
        capacity_error: nil,
        form_errors: %{},
        date_validation_errors: %{},
        date_form: date_form,
        membership_type: membership_type,
        active_tab: active_tab,
        can_book: can_book,
        booking_error_title: booking_error_title,
        booking_disabled_reason: booking_disabled_reason,
        active_bookings: active_bookings,
        buyout_refund_policy: buyout_refund_policy,
        room_refund_policy: room_refund_policy,
        date_tooltips: date_tooltips,
        load_radar: true
      )

    # If dates are present and user can book, initialize validation and room availability
    socket =
      if checkin_date && checkout_date && can_book do
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

  @impl true
  def handle_params(params, uri, socket) do
    # Parse query parameters, handling malformed/double-encoded URLs
    params = parse_query_params(params, uri)

    # Parse dates and guest counts from URL params
    {checkin_date, checkout_date} = parse_dates_from_params(params)
    guests_count = parse_guests_from_params(params)
    children_count = parse_children_from_params(params)
    requested_tab = parse_tab_from_params(params)
    booking_mode = parse_booking_mode_from_params(params) || :room

    # Check if user can book (re-check in case user state changed)
    user = socket.assigns.current_user

    # Load active bookings for the user (only if not already loaded in mount)
    active_bookings =
      if user && !socket.assigns[:active_bookings] do
        get_active_bookings(user.id)
      else
        socket.assigns[:active_bookings] || []
      end

    # Check if user can book (pass active_bookings to avoid duplicate query)
    {can_book, booking_error_title, booking_disabled_reason} =
      check_booking_eligibility(user, active_bookings)

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
    if checkin_date != socket.assigns.checkin_date ||
         checkout_date != socket.assigns.checkout_date ||
         guests_count != socket.assigns.guests_count ||
         children_count != socket.assigns.children_count ||
         booking_mode != socket.assigns.selected_booking_mode ||
         tab_changed do
      today = Date.utc_today()
      seasons = socket.assigns.seasons

      {current_season, season_start_date, season_end_date} =
        get_current_season_info_cached(seasons, today)

      max_booking_date = calculate_max_booking_date_cached(seasons, today)

      # Calculate restricted date range for family/lifetime members with 1 room booking
      membership_type = socket.assigns.membership_type || :none
      active_bookings = socket.assigns[:active_bookings] || []

      {restricted_min_date, restricted_max_date} =
        if membership_type in [:family, :lifetime] && length(active_bookings) > 0 do
          total_rooms = count_rooms_in_active_bookings(active_bookings)

          if total_rooms == 1 do
            calculate_restricted_date_range(active_bookings, max_booking_date)
          else
            {today, max_booking_date}
          end
        else
          {today, max_booking_date}
        end

      # Check if dates are actually restricted
      dates_restricted =
        dates_are_restricted?(restricted_min_date, restricted_max_date, today, max_booking_date)

      # Generate date tooltips for unavailable dates
      date_tooltips =
        generate_date_tooltips(restricted_min_date, restricted_max_date, today, :tahoe, seasons)

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
          page_title: "Tahoe Cabin",
          checkin_date: checkin_date,
          checkout_date: checkout_date,
          today: today,
          max_booking_date: max_booking_date,
          restricted_min_date: restricted_min_date,
          restricted_max_date: restricted_max_date,
          dates_restricted: dates_restricted,
          current_season: current_season,
          season_start_date: season_start_date,
          season_end_date: season_end_date,
          guests_count: guests_count,
          children_count: children_count,
          selected_booking_mode: booking_mode,
          selected_room_id: nil,
          selected_room_ids: [],
          guests_dropdown_open: false,
          available_rooms: [],
          calculated_price: nil,
          price_error: nil,
          form_errors: %{},
          date_form: date_form,
          date_validation_errors: %{},
          active_tab: active_tab,
          can_book: can_book,
          booking_error_title: booking_error_title,
          booking_disabled_reason: booking_disabled_reason,
          active_bookings: active_bookings,
          date_tooltips: date_tooltips
        )
        |> then(fn s ->
          # Only run validation/room updates if dates changed, not just tab
          if checkin_date != socket.assigns.checkin_date ||
               checkout_date != socket.assigns.checkout_date ||
               guests_count != socket.assigns.guests_count ||
               children_count != socket.assigns.children_count ||
               booking_mode != socket.assigns.selected_booking_mode do
            s
            |> enforce_season_booking_mode()
            |> validate_dates()
            |> update_available_rooms()
            |> calculate_price_if_ready()
          else
            s
          end
        end)

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

    # Recalculate restricted dates if needed
    membership_type = socket.assigns.membership_type || :none
    active_bookings = socket.assigns[:active_bookings] || []
    max_booking_date = socket.assigns.max_booking_date

    {restricted_min_date, restricted_max_date} =
      if membership_type in [:family, :lifetime] && length(active_bookings) > 0 do
        total_rooms = count_rooms_in_active_bookings(active_bookings)

        if total_rooms == 1 do
          calculate_restricted_date_range(active_bookings, max_booking_date)
        else
          {socket.assigns.today, max_booking_date}
        end
      else
        {socket.assigns.today, max_booking_date}
      end

    # Check if dates are actually restricted
    dates_restricted =
      dates_are_restricted?(
        restricted_min_date,
        restricted_max_date,
        socket.assigns.today,
        max_booking_date
      )

    # Generate date tooltips for unavailable dates
    date_tooltips =
      generate_date_tooltips(
        restricted_min_date,
        restricted_max_date,
        socket.assigns.today,
        :tahoe,
        socket.assigns.seasons
      )

    socket =
      socket
      |> assign(
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        restricted_min_date: restricted_min_date,
        restricted_max_date: restricted_max_date,
        dates_restricted: dates_restricted,
        selected_room_id: nil,
        selected_room_ids: [],
        available_rooms: [],
        calculated_price: nil,
        price_error: nil,
        form_errors: %{},
        date_form: date_form,
        date_validation_errors: %{},
        date_tooltips: date_tooltips
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
      <div class="max-w-screen-xl mx-auto flex flex-col px-4 space-y-6 lg:px-10">
        <div class="prose prose-zinc">
          <h1>Lake Tahoe Cabin</h1>
          <p>
            Select your dates and room(s) to make a reservation at our Lake Tahoe cabin.
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
                          <.badge>
                            <%= booking.reference_id %>
                          </.badge>
                          <%= if Ecto.assoc_loaded?(booking.rooms) && length(booking.rooms) > 0 do %>
                            <span class="text-sm text-zinc-600 font-medium">
                              <%= Enum.map_join(booking.rooms, ", ", fn room -> room.name end) %>
                            </span>
                          <% else %>
                            <span class="text-sm text-zinc-600 font-medium">Buyout</span>
                          <% end %>
                        </div>
                        <div class="text-sm text-zinc-600">
                          <div class="flex items-center gap-4">
                            <span>
                              <span class="font-medium">Check-in:</span> <%= format_date(
                                booking.checkin_date
                              ) %>
                            </span>
                            <span>
                              <span class="font-medium">Check-out:</span> <%= format_date(
                                booking.checkout_date
                              ) %>
                            </span>
                          </div>
                          <div class="mt-1">
                            <%= booking.guests_count %> <%= if booking.guests_count == 1,
                              do: "guest",
                              else: "guests" %>
                            <%= if booking.children_count > 0 do %>
                              , <%= booking.children_count %> <%= if booking.children_count == 1,
                                do: "child",
                                else: "children" %>
                            <% end %>
                          </div>
                        </div>
                      </div>
                      <div class="ml-4 flex flex-col items-end gap-2">
                        <%= if Date.compare(booking.checkout_date, Date.utc_today()) == :eq do %>
                          <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-amber-100 text-amber-800">
                            Checking out today
                          </span>
                        <% else %>
                          <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                            Active
                          </span>
                        <% end %>
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
              <h3 :if={@booking_error_title} class="text-sm font-semibold text-amber-900">
                <%= @booking_error_title %>
              </h3>
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
            "bg-white rounded-lg border border-zinc-200 p-6 space-y-6 min-h-[600px]",
            if(!@can_book, do: "relative opacity-60", else: "")
          ]}
        >
          <div
            :if={!@can_book}
            class="absolute inset-0 bg-white bg-opacity-50 rounded-lg pointer-events-none z-10"
          >
          </div>
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
                  min={@restricted_min_date}
                  max={@restricted_max_date}
                  disabled={!@can_book}
                  date_tooltips={@date_tooltips}
                  property={@property}
                  today={@today}
                />
              </div>
              <!-- Guests and Children Selection (Dropdown) -->
              <div class="md:col-span-1 py-1 ms-0 md:ms-4">
                <div id="guests-label" class="block text-sm font-semibold text-zinc-700 mb-2">
                  Guests
                </div>
                <div class="relative">
                  <!-- Dropdown Trigger -->
                  <button
                    type="button"
                    id="guests-dropdown-button"
                    phx-click="toggle-guests-dropdown"
                    disabled={!@can_book}
                    aria-labelledby="guests-label"
                    aria-expanded={@guests_dropdown_open}
                    aria-haspopup="true"
                    class="w-full px-3 py-2 border border-zinc-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500 bg-white text-left flex items-center justify-between disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    <span class="text-zinc-900">
                      <%= format_guests_display(@guests_count, @children_count) %>
                    </span>
                    <.icon
                      name="hero-chevron-down"
                      class={[
                        "w-5 h-5 text-zinc-500 transition-transform duration-200 ease-in-out",
                        if(@guests_dropdown_open, do: "rotate-180", else: "")
                      ]}
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
                        <div id="adults-label" class="block text-sm font-semibold text-zinc-700 mb-2">
                          Number of Adults
                        </div>
                        <div
                          class="flex items-center space-x-3"
                          role="group"
                          aria-labelledby="adults-label"
                        >
                          <button
                            type="button"
                            id="decrease-guests-button"
                            phx-click="decrease-guests"
                            disabled={@guests_count <= 1}
                            aria-label="Decrease number of adults"
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
                          <span
                            id="guests-count-display"
                            class="w-12 text-center font-medium text-lg text-zinc-900"
                            aria-live="polite"
                          >
                            <%= @guests_count %>
                          </span>
                          <button
                            type="button"
                            id="increase-guests-button"
                            phx-click="increase-guests"
                            aria-label="Increase number of adults"
                            class="w-10 h-10 rounded-full border-2 border-blue-700 bg-blue-700 hover:bg-blue-800 hover:border-blue-800 text-white flex items-center justify-center transition-all duration-200 font-semibold"
                          >
                            <.icon name="hero-plus" class="w-5 h-5" />
                          </button>
                        </div>
                      </div>
                      <!-- Children Counter -->
                      <div>
                        <div
                          id="children-label"
                          class="block text-sm font-semibold text-zinc-700 mb-2"
                        >
                          Number of Children (ages 5-17)
                        </div>
                        <div
                          class="flex items-center space-x-3"
                          role="group"
                          aria-labelledby="children-label"
                        >
                          <button
                            type="button"
                            id="decrease-children-button"
                            phx-click="decrease-children"
                            disabled={@children_count <= 0}
                            aria-label="Decrease number of children"
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
                          <span
                            id="children-count-display"
                            class="w-12 text-center font-medium text-lg text-zinc-900"
                            aria-live="polite"
                          >
                            <%= @children_count %>
                          </span>
                          <button
                            type="button"
                            id="increase-children-button"
                            phx-click="increase-children"
                            aria-label="Increase number of children"
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
            <p :if={@date_validation_errors[:season_date_range]} class="text-red-600 text-sm mt-1">
              <%= @date_validation_errors[:season_date_range] %>
            </p>
            <p :if={@date_validation_errors[:availability]} class="text-red-600 text-sm mt-1">
              <%= @date_validation_errors[:availability] %>
            </p>
          </div>
          <!-- Booking Mode Selection -->
          <div
            :if={@dates_restricted && @membership_type in [:family, :lifetime]}
            class="mt-2 p-3 bg-blue-50 border border-blue-200 rounded-md"
          >
            <div class="flex items-start">
              <div class="flex-shrink-0">
                <.icon name="hero-information-circle" class="h-5 w-5 text-blue-600" />
              </div>
              <div class="ms-2 flex-1">
                <p class="text-sm text-blue-800">
                  <strong>Second Room Booking:</strong>
                  Since you already have one room reserved, your second room booking must be within the same time period. The date range is restricted to ensure both bookings overlap and stay within the 4-night maximum.
                </p>
              </div>
            </div>
          </div>

          <div :if={@checkin_date}>
            <fieldset>
              <legend class="block text-sm font-semibold text-zinc-700 mb-2">
                Booking Type
              </legend>
              <form phx-change="booking-mode-changed">
                <div class="flex gap-4" role="radiogroup">
                  <label class="flex items-center">
                    <input
                      type="radio"
                      id="booking-mode-room"
                      name="booking_mode"
                      value="room"
                      checked={@selected_booking_mode == :room}
                      class="mr-2"
                    />
                    <span>Individual Room(s)</span>
                  </label>
                  <label class={[
                    "flex items-center",
                    if(not can_select_booking_mode?(@seasons, @checkin_date),
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
                      disabled={not can_select_booking_mode?(@seasons, @checkin_date)}
                      class={[
                        "mr-2",
                        if(not can_select_booking_mode?(@seasons, @checkin_date),
                          do: "cursor-not-allowed opacity-50",
                          else: ""
                        )
                      ]}
                      onclick={
                        if(not can_select_booking_mode?(@seasons, @checkin_date),
                          do: "return false;",
                          else: ""
                        )
                      }
                    />
                    <span class={
                      if(not can_select_booking_mode?(@seasons, @checkin_date),
                        do: "text-zinc-400",
                        else: ""
                      )
                    }>
                      Full Buyout
                    </span>
                  </label>
                </div>
              </form>
            </fieldset>
            <p
              :if={not can_select_booking_mode?(@seasons, @checkin_date)}
              class="text-sm text-zinc-500 mt-2 ml-6"
            >
              Full buyout is not available for the selected dates.
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
              </div>
            </div>
            <fieldset>
              <legend class="block text-sm font-semibold text-zinc-700 mb-4">
                <%= if can_select_multiple_rooms?(assigns) do %>
                  Select Room(s) <%= if length(@selected_room_ids) > 0,
                    do: "(#{length(@selected_room_ids)}/#{max_rooms_for_user(assigns)})",
                    else: "" %>
                <% else %>
                  Select Room
                <% end %>
              </legend>
              <div
                class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 items-stretch"
                role={if can_select_multiple_rooms?(assigns), do: "group", else: "radiogroup"}
              >
                <%= for room <- @available_rooms do %>
                  <% {availability, reason} = room.availability_status || {:available, nil} %>
                  <% is_unavailable = availability == :unavailable %>
                  <% max_rooms_reached =
                    can_select_multiple_rooms?(assigns) &&
                      length(@selected_room_ids) >= max_rooms_for_user(assigns) %>
                  <% room_already_selected =
                    (can_select_multiple_rooms?(assigns) && room.id in @selected_room_ids) ||
                      (!can_select_multiple_rooms?(assigns) && @selected_room_id == room.id) %>
                  <% guests_count = parse_guests_count(@guests_count) || 1 %>
                  <% children_count = parse_children_count(@children_count) || 0 %>
                  <% total_people = guests_count + children_count %>
                  <% only_one_person_selected = total_people == 1 %>
                  <% cannot_add_second_room =
                    can_select_multiple_rooms?(assigns) && only_one_person_selected &&
                      length(@selected_room_ids) > 0 && !room_already_selected %>
                  <% is_disabled =
                    (is_unavailable && !room_already_selected) ||
                      (max_rooms_reached && !room_already_selected) ||
                      cannot_add_second_room %>
                  <div class={[
                    "border rounded-lg overflow-hidden flex flex-col h-full",
                    if(is_disabled,
                      do: "border-zinc-200 bg-zinc-50 cursor-not-allowed opacity-60",
                      else:
                        "border-zinc-300 hover:border-blue-400 hover:shadow-md cursor-pointer transition-all"
                    )
                  ]}>
                    <label :if={!is_disabled} class="block cursor-pointer flex flex-col h-full">
                      <input
                        type={if can_select_multiple_rooms?(assigns), do: "checkbox", else: "radio"}
                        id={"room-#{room.id}"}
                        name={if can_select_multiple_rooms?(assigns), do: "room_ids", else: "room_id"}
                        value={room.id}
                        checked={
                          if can_select_multiple_rooms?(assigns) do
                            room.id in @selected_room_ids
                          else
                            @selected_room_id == room.id
                          end
                        }
                        aria-label={"Select #{room.name}"}
                        phx-click="room-changed"
                        phx-value-room-id={room.id}
                        class="sr-only"
                      />
                      <!-- Room Image with Alert Overlay -->
                      <div class="w-full h-48 bg-zinc-200 relative overflow-hidden">
                        <!-- Alert Overlay on Image -->
                        <div
                          :if={is_unavailable && reason}
                          class="absolute top-0 left-0 right-0 bg-amber-50 border-b border-amber-200 p-2 z-10"
                        >
                          <div class="flex items-start gap-2">
                            <.icon
                              name="hero-exclamation-triangle-solid"
                              class="w-4 h-4 text-amber-600 flex-shrink-0"
                            />
                            <p class="text-xs text-amber-800"><%= reason %></p>
                          </div>
                        </div>
                        <%= if room.image && room.image.id do %>
                          <!-- Render image with blur hash -->
                          <canvas
                            id={"blur-hash-room-#{room.id}"}
                            src={get_room_blur_hash(room.image)}
                            class="absolute inset-0 z-0 w-full h-full object-cover"
                            phx-hook="BlurHashCanvas"
                          >
                          </canvas>
                          <img
                            src={get_room_image_url(room.image)}
                            id={"image-room-#{room.id}"}
                            loading="lazy"
                            phx-hook="BlurHashImage"
                            class="absolute inset-0 z-[1] opacity-0 transition-opacity duration-300 ease-out w-full h-full object-cover"
                            alt={room.image.alt_text || room.image.title || "#{room.name} image"}
                          />
                        <% else %>
                          <!-- Placeholder when no image -->
                          <div class="absolute inset-0 flex items-center justify-center">
                            <div class="text-zinc-400 text-sm flex flex-col items-center justify-center">
                              <.icon name="hero-photo" class="w-20 h-20 mx-auto mb-2" />Room Image
                            </div>
                          </div>
                        <% end %>
                      </div>
                      <!-- Room Content -->
                      <div class="p-4 flex-1 flex flex-col">
                        <div class="flex items-start justify-between mb-2">
                          <div class="flex-1">
                            <div class="font-semibold text-zinc-900 text-lg"><%= room.name %></div>
                            <div class="text-sm text-zinc-600 mt-1">
                              <%= room.description %>
                            </div>
                          </div>
                          <div class="ml-3 flex-shrink-0">
                            <div class={
                              if (can_select_multiple_rooms?(assigns) && room.id in @selected_room_ids) or
                                   (!can_select_multiple_rooms?(assigns) &&
                                      @selected_room_id == room.id) do
                                "w-5 h-5 rounded border-2 flex items-center justify-center bg-blue-600 border-blue-600"
                              else
                                "w-5 h-5 rounded border-2 flex items-center justify-center border-zinc-300"
                              end
                            }>
                              <svg
                                :if={
                                  (can_select_multiple_rooms?(assigns) &&
                                     room.id in @selected_room_ids) or
                                    (!can_select_multiple_rooms?(assigns) &&
                                       @selected_room_id == room.id)
                                }
                                class="w-3 h-3 text-white"
                                fill="currentColor"
                                viewBox="0 0 20 20"
                              >
                                <path
                                  fill-rule="evenodd"
                                  d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                                  clip-rule="evenodd"
                                />
                              </svg>
                            </div>
                          </div>
                        </div>

                        <div class="flex items-center gap-2 text-xs text-zinc-500 mb-3">
                          <span>Max <%= room.capacity_max %> guests</span>
                          <span :if={room.min_billable_occupancy > 1}>
                            • Min <%= room.min_billable_occupancy %> guests
                          </span>
                        </div>

                        <div
                          :if={room.single_beds > 0 || room.queen_beds > 0 || room.king_beds > 0}
                          class="flex items-center gap-2 mb-3 text-xs text-zinc-500 mt-auto"
                        >
                          <span :if={room.single_beds > 0} class="flex items-center gap-1">
                            <%= raw(bed_icon_svg(:single, "w-4 h-4")) %>
                            <span><%= room.single_beds %> Twin</span>
                          </span>
                          <span :if={room.queen_beds > 0} class="flex items-center gap-1">
                            <%= raw(bed_icon_svg(:queen, "w-4 h-4")) %>
                            <span><%= room.queen_beds %> Queen</span>
                          </span>
                          <span :if={room.king_beds > 0} class="flex items-center gap-1">
                            <%= raw(bed_icon_svg(:king, "w-4 h-4")) %>
                            <span><%= room.king_beds %> King</span>
                          </span>
                        </div>

                        <div class="border-t border-zinc-200 pt-3">
                          <div class="text-sm text-zinc-900 font-medium">
                            <div :if={room.minimum_price}>
                              <%= MoneyHelper.format_money!(room.minimum_price) %> minimum
                              <span class="text-xs text-zinc-500 font-normal">
                                (<%= room.min_billable_occupancy %> guest min)
                              </span>
                            </div>
                            <div :if={!room.minimum_price}>
                              <%= MoneyHelper.format_money!(
                                room.adult_price_per_night || Money.new(45, :USD)
                              ) %> per adult
                            </div>
                          </div>
                          <div class="text-xs text-zinc-500 mt-1">
                            <%= MoneyHelper.format_money!(
                              room.children_price_per_night || Money.new(25, :USD)
                            ) %> per child
                          </div>
                        </div>
                      </div>
                    </label>
                    <div :if={is_disabled} class="block cursor-not-allowed flex flex-col h-full">
                      <input
                        type={if can_select_multiple_rooms?(assigns), do: "checkbox", else: "radio"}
                        name={if can_select_multiple_rooms?(assigns), do: "room_ids", else: "room_id"}
                        value={room.id}
                        checked={false}
                        disabled={true}
                        class="sr-only"
                        readonly
                      />
                      <!-- Room Image with Alert Overlay -->
                      <div class="w-full h-48 bg-zinc-200 relative overflow-hidden">
                        <!-- Alert Overlay on Image -->
                        <div
                          :if={is_unavailable && reason}
                          class="absolute top-0 left-0 right-0 bg-amber-50 border-b border-amber-200 p-2 z-10"
                        >
                          <div class="flex items-start gap-2">
                            <.icon
                              name="hero-exclamation-triangle-solid"
                              class="w-4 h-4 text-amber-600 flex-shrink-0"
                            />
                            <p class="text-xs text-amber-800"><%= reason %></p>
                          </div>
                        </div>
                        <%= if room.image && room.image.id do %>
                          <!-- Render image with blur hash -->
                          <canvas
                            id={"blur-hash-room-disabled-#{room.id}"}
                            src={get_room_blur_hash(room.image)}
                            class="absolute inset-0 z-0 w-full h-full object-cover"
                            phx-hook="BlurHashCanvas"
                          >
                          </canvas>
                          <img
                            src={get_room_image_url(room.image)}
                            id={"image-room-disabled-#{room.id}"}
                            loading="lazy"
                            phx-hook="BlurHashImage"
                            class="absolute inset-0 z-[1] opacity-0 transition-opacity duration-300 ease-out w-full h-full object-cover"
                            alt={room.image.alt_text || room.image.title || "#{room.name} image"}
                          />
                        <% else %>
                          <!-- Placeholder when no image -->
                          <div class="absolute inset-0 flex items-center justify-center">
                            <div class="text-zinc-400 text-sm flex flex-col items-center justify-center">
                              <.icon name="hero-photo" class="w-20 h-20 mx-auto mb-2" />Room Image
                            </div>
                          </div>
                        <% end %>
                      </div>
                      <!-- Room Content -->
                      <div class="p-4 flex-1 flex flex-col">
                        <div class="flex items-start justify-between mb-2">
                          <div class="flex-1">
                            <div class="font-semibold text-zinc-900 text-lg"><%= room.name %></div>
                            <div class="text-sm text-zinc-600 mt-1">
                              <%= room.description %>
                            </div>
                          </div>
                          <div class="ml-3 flex-shrink-0">
                            <div class="w-5 h-5 rounded border-2 border-zinc-300"></div>
                          </div>
                        </div>

                        <div class="flex items-center gap-2 text-xs text-zinc-500 mb-3">
                          <span>Max <%= room.capacity_max %> guests</span>
                          <span :if={room.min_billable_occupancy > 1}>
                            • Min <%= room.min_billable_occupancy %> guests
                          </span>
                        </div>

                        <div
                          :if={room.single_beds > 0 || room.queen_beds > 0 || room.king_beds > 0}
                          class="flex items-center gap-2 mb-3 text-xs text-zinc-500 mt-auto"
                        >
                          <span :if={room.single_beds > 0} class="flex items-center gap-1">
                            <%= raw(bed_icon_svg(:single, "w-4 h-4")) %>
                            <span><%= room.single_beds %> Twin</span>
                          </span>
                          <span :if={room.queen_beds > 0} class="flex items-center gap-1">
                            <%= raw(bed_icon_svg(:queen, "w-4 h-4")) %>
                            <span><%= room.queen_beds %> Queen</span>
                          </span>
                          <span :if={room.king_beds > 0} class="flex items-center gap-1">
                            <%= raw(bed_icon_svg(:king, "w-4 h-4")) %>
                            <span><%= room.king_beds %> King</span>
                          </span>
                        </div>

                        <div class="border-t border-zinc-200 pt-3">
                          <div class="text-sm text-zinc-900 font-medium">
                            <div :if={room.minimum_price}>
                              <%= MoneyHelper.format_money!(room.minimum_price) %> minimum
                              <span class="text-xs text-zinc-500 font-normal">
                                (<%= room.min_billable_occupancy %> guest min)
                              </span>
                            </div>
                            <div :if={!room.minimum_price}>
                              <%= MoneyHelper.format_money!(
                                room.adult_price_per_night || Money.new(45, :USD)
                              ) %> per adult
                            </div>
                          </div>
                          <div class="text-xs text-zinc-500 mt-1">
                            <%= MoneyHelper.format_money!(
                              room.children_price_per_night || Money.new(25, :USD)
                            ) %> per child
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            </fieldset>
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
                  length(@selected_room_ids) < max_rooms_for_user(assigns) &&
                  (parse_guests_count(@guests_count) || 1) > 1
              }
              class="text-blue-600 text-sm mt-2"
            >
              <.icon name="hero-light-bulb-solid" class="w-4 h-4 text-blue-600 inline-block me-1" />
              Family membership: You can book up to <%= max_rooms_for_user(assigns) %> rooms in the same reservation.
            </p>
            <p
              :if={
                can_select_multiple_rooms?(assigns) &&
                  length(@selected_room_ids) > 0 &&
                  (parse_guests_count(@guests_count) || 1) +
                    (parse_children_count(@children_count) || 0) == 1
              }
              class="text-amber-600 text-sm mt-2"
            >
              <.icon
                name="hero-exclamation-triangle-solid"
                class="w-4 h-4 text-amber-600 inline-block me-1"
              />
              Cannot book multiple rooms with only 1 person. Please select more people to book additional rooms.
            </p>
          </div>
          <!-- Buyout Selection (for buyout bookings) -->
          <div :if={@selected_booking_mode == :buyout && @checkin_date && @checkout_date}>
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
              </div>
            </div>

            <div class={[
              "border-2 rounded-lg p-6 text-center mb-6",
              if(@date_validation_errors[:availability],
                do: "border-red-200 bg-red-50",
                else: "border-indigo-100 bg-indigo-50"
              )
            ]}>
              <div class={[
                "inline-flex items-center justify-center w-12 h-12 rounded-full mb-4",
                if(@date_validation_errors[:availability],
                  do: "bg-red-100 text-red-600",
                  else: "bg-indigo-100 text-indigo-600"
                )
              ]}>
                <.icon
                  name={
                    if @date_validation_errors[:availability],
                      do: "hero-exclamation-circle",
                      else: "hero-home-modern"
                  }
                  class="w-6 h-6"
                />
              </div>
              <h3 class={[
                "text-xl font-semibold mb-2",
                if(@date_validation_errors[:availability],
                  do: "text-red-900",
                  else: "text-indigo-900"
                )
              ]}>
                <%= if @date_validation_errors[:availability],
                  do: "Buyout Unavailable",
                  else: "Full Cabin Buyout" %>
              </h3>
              <p class={[
                "mb-4 max-w-md mx-auto",
                if(@date_validation_errors[:availability],
                  do: "text-red-800",
                  else: "text-indigo-800"
                )
              ]}>
                <%= if @date_validation_errors[:availability] do %>
                  <%= @date_validation_errors[:availability] %>
                <% else %>
                  You are reserving the entire Tahoe cabin for your group.
                  This includes exclusive use of all 7 bedrooms, 3 bathrooms, and the sauna.
                <% end %>
              </p>
              <div
                :if={!@date_validation_errors[:availability]}
                class="flex flex-wrap justify-center gap-3 text-sm font-medium text-indigo-700"
              >
                <span class="bg-white px-3 py-1 rounded-full border border-indigo-200">
                  Up to 17 Guests
                </span>
                <span class="bg-white px-3 py-1 rounded-full border border-indigo-200">
                  Exclusive Access
                </span>
                <span class="bg-white px-3 py-1 rounded-full border border-indigo-200">
                  Fixed Nightly Rate
                </span>
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
                  <span :if={@selected_booking_mode == :room}>
                    <strong>Individual Room(s):</strong>
                    You are booking specific rooms. You will share common areas (kitchen, living room, sauna) with other members.
                  </span>
                  <span :if={@selected_booking_mode == :buyout}>
                    <strong>Full Buyout (Exclusive Rental):</strong>
                    You'll have the entire cabin exclusively for your group. Perfect for larger groups or special occasions!
                  </span>
                </p>
              </div>
              <!-- Price Breakdown -->
              <div :if={@price_breakdown} class="border-t border-zinc-200 pt-4">
                <h4 class="text-sm font-semibold text-zinc-700 mb-3">Price Breakdown</h4>
                <div class="space-y-2 text-sm">
                  <!-- Buyout Breakdown -->
                  <div :if={@selected_booking_mode == :buyout} class="flex justify-between text-sm">
                    <span class="text-zinc-600">
                      Full Buyout
                      <%= if @price_breakdown.nights && @price_breakdown.price_per_night do %>
                        (<%= MoneyHelper.format_money!(@price_breakdown.price_per_night) %> × <%= @price_breakdown.nights %> night<%= if @price_breakdown.nights !=
                                                                                                                                           1,
                                                                                                                                         do:
                                                                                                                                           "s",
                                                                                                                                         else:
                                                                                                                                           "" %>)
                      <% end %>
                    </span>
                    <span class="font-medium text-zinc-900">
                      <%= MoneyHelper.format_money!(@calculated_price) %>
                    </span>
                  </div>
                  <!-- Room Breakdown -->
                  <div :if={@selected_booking_mode == :room}>
                    <div
                      :if={@price_breakdown[:using_minimum_pricing]}
                      class="mb-2 p-2 bg-amber-50 border border-amber-200 rounded-md"
                    >
                      <div class="flex items-start gap-2">
                        <.icon
                          name="hero-information-circle"
                          class="w-4 h-4 text-amber-600 flex-shrink-0 mt-0.5"
                        />
                        <p class="text-xs text-amber-800">
                          <strong>Minimum occupancy pricing applied:</strong>
                          You're being charged for <%= @price_breakdown[:billable_people] %> adults to meet the room's minimum occupancy requirement (you selected <%= @price_breakdown[
                            :guests_count
                          ] %> adult<%= if @price_breakdown[:guests_count] != 1, do: "s", else: "" %>).
                        </p>
                      </div>
                    </div>
                    <div class="flex justify-between text-sm">
                      <span class="text-zinc-600">
                        Base Price
                        <%= if @price_breakdown.nights && @price_breakdown[:adult_price_per_night] do %>
                          <% # Always use billable_people for display (respects min_billable_occupancy)
                          # For multiple rooms with use_actual_guests=true, billable_people equals guests_count
                          # For single room, billable_people respects room's min_billable_occupancy
                          adult_count =
                            @price_breakdown[:billable_people] || @price_breakdown[:guests_count] ||
                              0 %> (<%= adult_count %> <%= if adult_count ==
                                                                1,
                                                              do: "adult",
                                                              else: "adults" %> × <%= MoneyHelper.format_money!(
                            @price_breakdown.adult_price_per_night
                          ) %> × <%= @price_breakdown.nights %> night<%= if @price_breakdown.nights !=
                                                                              1,
                                                                            do: "s",
                                                                            else: "" %>)
                          <%= if @price_breakdown[:using_minimum_pricing] do %>
                            <span class="text-amber-600 text-xs ml-1">(minimum)</span>
                          <% end %>
                        <% end %>
                      </span>
                      <span class="font-medium text-zinc-900">
                        <%= if @price_breakdown[:base],
                          do: MoneyHelper.format_money!(@price_breakdown.base) %>
                      </span>
                    </div>
                    <div
                      :if={@price_breakdown[:children] && @price_breakdown[:children_per_night]}
                      class="flex justify-between text-sm mt-2"
                    >
                      <span class="text-zinc-600">
                        Children (5-17)
                        <%= if @price_breakdown.nights && @price_breakdown[:children_price_per_night] do %>
                          (<%= @price_breakdown[:children_count] || 0 %> <%= if (@price_breakdown[
                                                                                   :children_count
                                                                                 ] ||
                                                                                   0) == 1,
                                                                                do: "child",
                                                                                else: "children" %> × <%= MoneyHelper.format_money!(
                            @price_breakdown.children_price_per_night
                          ) %> × <%= @price_breakdown.nights %> night<%= if @price_breakdown.nights !=
                                                                              1,
                                                                            do: "s",
                                                                            else: "" %>)
                        <% end %>
                      </span>
                      <span class="font-medium text-zinc-900">
                        <%= MoneyHelper.format_money!(@price_breakdown.children) %>
                      </span>
                    </div>
                  </div>
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
          <p :if={@capacity_error} class="text-red-600 text-sm mt-2">
            <%= @capacity_error %>
          </p>
          <!-- Restricted Date Range Message -->

          <!-- Submit Button -->
          <div>
            <button
              :if={@can_book}
              phx-click="create-booking"
              disabled={
                !can_submit_booking?(
                  @selected_booking_mode,
                  @checkin_date,
                  @checkout_date,
                  get_selected_rooms_for_submit(assigns),
                  @capacity_error,
                  @price_error,
                  @form_errors,
                  @date_validation_errors
                )
              }
              class={
                if can_submit_booking?(
                     @selected_booking_mode,
                     @checkin_date,
                     @checkout_date,
                     get_selected_rooms_for_submit(assigns),
                     @capacity_error,
                     @price_error,
                     @form_errors,
                     @date_validation_errors
                   ) do
                  "w-full bg-blue-600 hover:bg-blue-700 text-white font-semibold py-3 px-4 rounded-md transition duration-200"
                else
                  "w-full bg-zinc-300 text-zinc-600 font-semibold py-3 px-4 rounded-md cursor-not-allowed opacity-50"
                end
              }
            >
              Create Booking
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
              Welcome to the <strong>YSC Tahoe Cabin</strong>
              — your year-round retreat in the heart of Lake Tahoe!
            </p>
            <p>
              Since <strong>1993</strong>, the YSC has proudly owned this beautiful cabin, located just minutes from Tahoe City, on the
              <strong>west shore</strong>
              of <strong>Lake Tahoe</strong>.
            </p>
          </div>
          <!-- Important Notice -->
          <h2>💡 Please Remember</h2>
          <p>
            The Tahoe Cabin is <strong>your cabin — not a hotel.</strong>
            To ensure everyone enjoys their stay at a reasonable rate, please follow the guidelines below.
          </p>
          <!-- About the Cabin -->
          <div>
            <h2>🌲 About the Cabin</h2>
            <p>
              The Lake Tahoe region offers endless outdoor opportunities:
            </p>
            <ul>
              <li><strong>Winter:</strong> Ski and snowboard at nearby resorts</li>
              <li><strong>Summer:</strong> Hike, bike, and enjoy the lake</li>
              <li><strong>Year-Round:</strong> Experience stunning mountain and lake views</li>
            </ul>
            <p class="font-semibold">Cabin Features:</p>
            <ul>
              <li>7 bedrooms</li>
              <li>3 bathrooms</li>
              <li>Traditional Scandinavian sauna</li>
              <li>Sleeps up to 17 guests</li>
              <li>Fully equipped kitchen</li>
              <li>Wood fireplace</li>
              <li>During summer season the cabin has kayaks available for use</li>
            </ul>
            <p>
              <strong>📍 Location:</strong>
              South of Tahoe City, near the lake's west shore and just minutes from <strong>Homewood Ski Resort</strong>. Palisades Tahoe (site of the 1960 Winter Olympics) and Alpine Meadows are ~20 minutes away.
            </p>

            <YscWeb.Components.ImageCarousel.image_carousel
              id="about-the-tahoe-cabin-carousel"
              images={[
                %{src: ~p"/images/tahoe/tahoe_cabin_main.webp", alt: "Tahoe Cabin Exterior"},
                %{src: ~p"/images/tahoe/tahoe_room_1.webp", alt: "Tahoe Cabin Room 1"},
                %{src: ~p"/images/tahoe/tahoe_room_2.webp", alt: "Tahoe Cabin Room 2"},
                %{src: ~p"/images/tahoe/tahoe_room_4.webp", alt: "Tahoe Cabin Room 4"},
                %{src: ~p"/images/tahoe/tahoe_room_5.webp", alt: "Tahoe Cabin Room 5"},
                %{src: ~p"/images/tahoe/tahoe_room_6.webp", alt: "Tahoe Cabin Room 6"},
                %{src: ~p"/images/tahoe/tahoe_room_7.webp", alt: "Tahoe Cabin Room 7"}
              ]}
              class="my-8"
            />
          </div>
          <!-- Reservations & Booking (Collapsible) -->
          <details class="border border-zinc-200 rounded-lg p-4 bg-zinc-50">
            <summary class="cursor-pointer font-semibold text-lg text-zinc-900 mb-4 list-none flex items-center justify-between">
              <span class="flex items-center">
                <span class="mr-2">🗓️</span>
                <span>Reservations & Booking</span>
              </span>
              <.icon
                name="hero-chevron-down"
                class="w-5 h-5 text-zinc-500 chevron-icon flex-shrink-0"
              />
            </summary>
            <div>
              <div>
                <h3 class="font-semibold text-zinc-900 mb-2">How to Reserve</h3>
                <ul>
                  <li>Use the <strong>Reservation Page</strong> to check availability.</li>
                  <li>View rooms on the <strong>Accommodations Page</strong> before booking.</li>
                  <li>All bookings must be made <strong>through the website</strong>.</li>
                  <li>
                    To cancel, use the <strong>"Cancel My Booking"</strong>
                    link in your confirmation email.
                  </li>
                  <li>See the Cancellation Policy below for details.</li>
                </ul>
              </div>
              <div>
                <h3>Booking Rules (Quick Reference)</h3>
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
                        <td class="py-2 pr-4 font-semibold">Maximum Stay</td>
                        <td class="py-2">4 nights per booking</td>
                      </tr>
                      <tr class="border-b border-zinc-200">
                        <td class="py-2 pr-4 font-semibold">Weekend Policy</td>
                        <td class="py-2">Saturday bookings must include Sunday</td>
                      </tr>
                      <tr class="border-b border-zinc-200">
                        <td class="py-2 pr-4 font-semibold">Active Bookings</td>
                        <td class="py-2">One active booking per member</td>
                      </tr>
                      <tr class="border-b border-zinc-200">
                        <td class="py-2 pr-4 font-semibold">Winter</td>
                        <td class="py-2">Individual rooms only</td>
                      </tr>
                      <tr class="border-b border-zinc-200">
                        <td class="py-2 pr-4 font-semibold">Summer</td>
                        <td class="py-2">Rooms or full cabin allowed</td>
                      </tr>
                      <tr class="border-b border-zinc-200">
                        <td class="py-2 pr-4 font-semibold">Membership Limits</td>
                        <td class="py-2">Family/Lifetime: 2 rooms<br />Single: 1 room</td>
                      </tr>
                      <tr>
                        <td class="py-2 pr-4 font-semibold">Children Pricing</td>
                        <td class="py-2">5–17 years: $25/night<br />Under 5: Free</td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
          </details>
          <!-- Getting There (Collapsible) -->
          <details class="border border-zinc-200 rounded-lg p-4 bg-zinc-50">
            <summary class="cursor-pointer font-semibold text-lg text-zinc-900 mb-4 list-none flex items-center justify-between">
              <span class="flex items-center">
                <span class="mr-2">🚗</span>
                <span>Getting There</span>
              </span>
              <.icon
                name="hero-chevron-down"
                class="w-5 h-5 text-zinc-500 chevron-icon flex-shrink-0"
              />
            </summary>
            <div>
              <div>
                <p class="font-semibold mb-2">Address:</p>
                <p class="mb-4">2685 Cedar Lane<br />Homewood, CA 96141</p>
              </div>

              <div class="flex flex-col items-center not-prose my-6">
                <.live_component
                  id="tahoe-cabin-map"
                  module={YscWeb.Components.MapComponent}
                  latitude={39.12591794747629}
                  longitude={-120.16648676079016}
                  locked={true}
                  class="my-4"
                />

                <YscWeb.Components.MapNavigationButtons.map_navigation_buttons
                  latitude={39.12591794747629}
                  longitude={-120.16648676079016}
                  class="w-full"
                />
              </div>

              <div>
                <h3 class="font-semibold text-zinc-900 mb-2">From the Bay Area</h3>
                <ol class="list-decimal list-inside space-y-2">
                  <li>Take <strong>I-80 East</strong> toward Reno.</li>
                  <li>Exit at <strong>Truckee</strong>, onto <strong>Highway 89 South</strong>.</li>
                  <li>
                    In <strong>Tahoe City</strong>, turn right at the first light to stay on Hwy 89.
                  </li>
                  <li>
                    After ~3 miles, turn <strong>right onto Timberland Lane</strong>
                    (look for the Timberland totem pole).
                  </li>
                  <li>Turn <strong>left onto Cedar Lane</strong> — the cabin is on your left.</li>
                </ol>
              </div>
              <div>
                <p class="text-sm text-zinc-600">
                  <strong>Transportation Notes:</strong>
                  Public transportation is limited — <strong>driving is recommended.</strong>
                  <strong>Carpooling</strong>
                  is encouraged to reduce parking strain and environmental impact.
                </p>
              </div>
            </div>
          </details>
          <!-- Winter Driving & Weather Tips (Collapsible) -->
          <details class="border border-blue-200 rounded-lg p-4 bg-blue-50">
            <summary class="cursor-pointer font-semibold text-lg text-blue-900 mb-4 list-none flex items-center justify-between">
              <span class="flex items-center">
                <span class="mr-2">❄️</span>
                <span>Winter Driving & Weather Tips</span>
              </span>
              <.icon
                name="hero-chevron-down"
                class="w-5 h-5 text-blue-600 chevron-icon flex-shrink-0"
              />
            </summary>
            <div>
              <ul class="list-disc list-inside space-y-2">
                <li>
                  Always carry <strong>snow chains</strong>
                  or use a <strong>4WD vehicle with snow tires</strong>.
                </li>
                <li>Check <strong>road and weather conditions</strong> before traveling.</li>
              </ul>
              <div>
                <p class="font-semibold mb-2">Helpful Resources:</p>
                <ul class="list-disc list-inside space-y-1">
                  <li>
                    <a
                      href="https://dot.ca.gov/travel/winter-driving-tips"
                      target="_blank"
                      class="text-blue-700 hover:text-blue-900 underline"
                    >
                      California Winter Driving Tips
                    </a>
                  </li>
                  <li>
                    Caltrans Road Info:
                    <a href="tel:8004277623" class="text-blue-700 hover:text-blue-900 underline">
                      (800) 427-7623
                    </a>
                  </li>
                  <li>
                    Twitter:
                    <a
                      href="https://twitter.com/CHP_Truckee"
                      target="_blank"
                      class="text-blue-700 hover:text-blue-900 underline"
                    >
                      @CHP_Truckee
                    </a>
                    ,
                    <a
                      href="https://twitter.com/CaltransDist3"
                      target="_blank"
                      class="text-blue-700 hover:text-blue-900 underline"
                    >
                      @CaltransDist3
                    </a>
                    ,
                    <a
                      href="https://twitter.com/NWSReno"
                      target="_blank"
                      class="text-blue-700 hover:text-blue-900 underline"
                    >
                      @NWSReno
                    </a>
                  </li>
                </ul>
              </div>
            </div>
          </details>
          <!-- Parking & Transportation (Collapsible) -->
          <details class="border border-zinc-200 rounded-lg p-4 bg-zinc-50">
            <summary class="cursor-pointer font-semibold text-lg text-zinc-900 mb-4 list-none flex items-center justify-between">
              <span class="flex items-center">
                <span class="mr-2">🚙</span>
                <span>Parking & Transportation</span>
              </span>
              <.icon
                name="hero-chevron-down"
                class="w-5 h-5 text-zinc-500 chevron-icon flex-shrink-0"
              />
            </summary>
            <div>
              <div>
                <p class="font-semibold mb-2">Local Services:</p>
                <ul class="list-disc list-inside space-y-1">
                  <li>
                    <strong>Tahoe Bus Transit:</strong>
                    <a href="tel:5305816365" class="text-blue-600 hover:text-blue-800 underline">
                      (530) 581-6365
                    </a>
                  </li>
                  <li>
                    <strong>Tahoe Taxi:</strong>
                    <a href="tel:5305463181" class="text-blue-600 hover:text-blue-800 underline">
                      (530) 546-3181
                    </a>
                  </li>
                </ul>
              </div>
              <div>
                <p class="font-semibold mb-2">Parking Rules:</p>
                <ul class="list-disc list-inside space-y-1">
                  <li>Limited parking — <strong>carpool if possible.</strong></li>
                  <li>You may need to move vehicles to accommodate others.</li>
                  <li>
                    <strong>No street parking Nov 1 – May 1</strong>
                    (towing enforced for snow removal).
                  </li>
                  <li>Do not block driveways or neighbors' access.</li>
                </ul>
              </div>
            </div>
          </details>
          <!-- Bear Safety Instructions (Collapsible) -->
          <details class="border border-red-200 rounded-lg p-4 bg-red-50">
            <summary class="cursor-pointer font-semibold text-lg text-red-900 mb-4 list-none flex items-center justify-between">
              <span class="flex items-center">
                <span class="mr-2">🐻</span>
                <span>Bear Safety Instructions</span>
              </span>
              <.icon name="hero-chevron-down" class="w-5 h-5 text-red-600 chevron-icon flex-shrink-0" />
            </summary>
            <div>
              <p>
                The cabin's deck is surrounded by <strong>electric bear wire</strong>
                — it won't harm you but must be handled properly.
              </p>
              <div>
                <h3 class="font-semibold mb-2">To Enter</h3>
                <ol class="list-decimal list-inside space-y-1">
                  <li>
                    Grab the <strong>top black handle</strong>
                    and disconnect it (disables the circuit).
                  </li>
                  <li>Remove the second and third wires.</li>
                </ol>
              </div>
              <div>
                <h3 class="font-semibold mb-2">When Leaving or at Night</h3>
                <ol class="list-decimal list-inside space-y-1">
                  <li>Replace the wires <strong>from bottom to top</strong>.</li>
                  <li>Connect lowest wire first, then middle, then top (reactivates barrier).</li>
                </ol>
              </div>
              <p class="text-sm">
                Always secure garbage cans and remove all food waste from outdoor areas.
              </p>
            </div>
          </details>
          <!-- Cancellation Policy (Collapsible) -->
          <details class="border border-zinc-200 rounded-lg p-4 bg-zinc-50">
            <summary class="cursor-pointer font-semibold text-lg text-zinc-900 mb-4 list-none flex items-center justify-between">
              <span class="flex items-center">
                <span class="mr-2">🧾</span>
                <span>Cancellation Policy</span>
              </span>
              <.icon
                name="hero-chevron-down"
                class="w-5 h-5 text-zinc-500 chevron-icon flex-shrink-0"
              />
            </summary>
            <div>
              <%= if @buyout_refund_policy do %>
                <div>
                  <h3 class="font-semibold text-zinc-900 mb-2">
                    <%= if @buyout_refund_policy.name,
                      do: @buyout_refund_policy.name,
                      else: "Full Cabin Bookings" %>
                  </h3>
                  <%= if @buyout_refund_policy.description do %>
                    <p class="text-sm text-zinc-600 mb-2"><%= @buyout_refund_policy.description %></p>
                  <% end %>
                  <%= if @buyout_refund_policy.rules && length(@buyout_refund_policy.rules) > 0 do %>
                    <ul class="list-disc list-inside space-y-1">
                      <%= for rule <- @buyout_refund_policy.rules do %>
                        <li>
                          <%= if rule.description && rule.description != "" do %>
                            <%= rule.description %>
                          <% else %>
                            <%= raw(format_refund_rule(rule)) %>
                          <% end %>
                        </li>
                      <% end %>
                    </ul>
                  <% end %>
                </div>
              <% end %>
              <%= if @room_refund_policy do %>
                <div class={if @buyout_refund_policy, do: "mt-4", else: ""}>
                  <h3 class="font-semibold text-zinc-900 mb-2">
                    <%= if @room_refund_policy.name,
                      do: @room_refund_policy.name,
                      else: "Individual Rooms" %>
                  </h3>
                  <%= if @room_refund_policy.description do %>
                    <p class="text-sm text-zinc-600 mb-2"><%= @room_refund_policy.description %></p>
                  <% end %>
                  <%= if @room_refund_policy.rules && length(@room_refund_policy.rules) > 0 do %>
                    <ul class="list-disc list-inside space-y-1">
                      <%= for rule <- @room_refund_policy.rules do %>
                        <li>
                          <%= if rule.description && rule.description != "" do %>
                            <%= rule.description %>
                          <% else %>
                            <%= raw(format_refund_rule(rule)) %>
                          <% end %>
                        </li>
                      <% end %>
                    </ul>
                  <% end %>
                </div>
              <% end %>
              <div class="bg-zinc-100 rounded p-3 text-sm mt-4">
                <p class="mb-2"><strong>Notes:</strong></p>
                <ul class="list-disc list-inside space-y-1">
                  <li>Members are responsible for the behavior and payments of their guests.</li>
                  <li>
                    <strong>Road closure cancellations</strong>
                    may be credited for a future stay (contact the Cabin Master).
                  </li>
                  <li>
                    <strong>Cash refunds</strong>
                    incur a <strong>3% processing fee</strong>
                    to cover credit card costs.
                  </li>
                </ul>
              </div>
            </div>
          </details>
          <!-- Cabin Rules & Etiquette (Collapsible) -->
          <details class="border border-zinc-200 rounded-lg p-4 bg-zinc-50">
            <summary class="cursor-pointer font-semibold text-lg text-zinc-900 mb-4 list-none flex items-center justify-between">
              <span class="flex items-center">
                <span class="mr-2">🧺</span>
                <span>Cabin Rules & Etiquette</span>
              </span>
              <.icon
                name="hero-chevron-down"
                class="w-5 h-5 text-zinc-500 chevron-icon flex-shrink-0"
              />
            </summary>
            <div>
              <div>
                <h3 class="font-semibold text-zinc-900 mb-2">General Guidelines</h3>
                <ul class="list-disc list-inside space-y-1">
                  <li>Treat the cabin as your own — it's <strong>not a hotel</strong>.</li>
                  <li>Respect quiet hours (<strong>10:00 PM – 7:00 AM</strong>).</li>
                  <li>Be considerate — stairs and hallways carry sound easily.</li>
                </ul>
              </div>
              <div>
                <h3 class="font-semibold text-zinc-900 mb-2">Common Areas & Storage</h3>
                <ul class="list-disc list-inside space-y-1">
                  <li>Keep personal items out of shared spaces.</li>
                  <li>Store <strong>ski boots</strong> in the laundry room racks.</li>
                  <li>Store other gear in the <strong>outside stairwell</strong>.</li>
                </ul>
              </div>
              <div>
                <h3 class="font-semibold text-zinc-900 mb-2">Pets</h3>
                <p>No pets are allowed — <strong>no exceptions.</strong></p>
              </div>
              <div>
                <h3 class="font-semibold text-zinc-900 mb-2">Smoking & Vaping</h3>
                <p><strong>Prohibited</strong> indoors and on covered decks.</p>
              </div>
              <div>
                <h3 class="font-semibold text-zinc-900 mb-2">Children</h3>
                <p>For safety, children should not play on or near the stairs.</p>
              </div>
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
              <p class="font-semibold">
                Please note: <strong>linens and towels are not provided.</strong>
              </p>
              <p class="font-semibold mb-2">Bring:</p>
              <ul class="list-disc list-inside space-y-1">
                <li>Sheets, towels, sleeping bags, and pillowcases</li>
                <li>Food (kitchen includes microwave & basic spices)</li>
                <li>Fire starters or kindling</li>
              </ul>
              <div class="bg-zinc-100 rounded p-3 text-sm mt-3">
                <p>
                  Firewood under the deck may be damp — best for sustaining fires, not starting them.
                </p>
              </div>
            </div>
          </details>
          <!-- Rates & Seasonal Rules (Collapsible) -->
          <details class="border border-zinc-200 rounded-lg p-4 bg-zinc-50">
            <summary class="cursor-pointer font-semibold text-lg text-zinc-900 mb-4 list-none flex items-center justify-between">
              <span class="flex items-center">
                <span class="mr-2">💰</span>
                <span>Rates & Seasonal Rules</span>
              </span>
              <.icon
                name="hero-chevron-down"
                class="w-5 h-5 text-zinc-500 chevron-icon flex-shrink-0"
              />
            </summary>
            <div>
              <div>
                <p class="font-semibold mb-2">Per-Person, Per-Night Rates</p>
                <ul class="list-disc list-inside space-y-1">
                  <li>Adults: <strong>$45</strong></li>
                  <li>Children (5–17): <strong>$25</strong></li>
                  <li>Children under 5: <strong>Free</strong></li>
                </ul>
              </div>
              <div>
                <p class="font-semibold mb-2">Seasonal Availability</p>
                <ul class="list-disc list-inside space-y-1">
                  <li>
                    <strong>Summer (May 1 – Nov 30):</strong>
                    Full-cabin or room reservations allowed (up to 17 guests)
                  </li>
                  <li><strong>Winter (Dec – Apr):</strong> Individual room bookings only</li>
                </ul>
              </div>
            </div>
          </details>
          <!-- Cleanliness & Chores (Collapsible) -->
          <details class="border border-zinc-200 rounded-lg p-4 bg-zinc-50">
            <summary class="cursor-pointer font-semibold text-lg text-zinc-900 mb-4 list-none flex items-center justify-between">
              <span class="flex items-center">
                <span class="mr-2">🧹</span>
                <span>Cleanliness & Chores</span>
              </span>
              <.icon
                name="hero-chevron-down"
                class="w-5 h-5 text-zinc-500 chevron-icon flex-shrink-0"
              />
            </summary>
            <div>
              <p>
                Keeping the cabin affordable depends on everyone pitching in!
              </p>
              <div>
                <p class="font-semibold mb-2">Guests must:</p>
                <ul class="list-disc list-inside space-y-1">
                  <li>Clean up after themselves</li>
                  <li>Strip and clean their rooms</li>
                  <li>Wash, dry, and store any used club bedding</li>
                  <li>Leave the kitchen spotless and remove all food</li>
                  <li>Secure bear-proof garbage lids</li>
                </ul>
              </div>
              <div class="bg-zinc-100 rounded p-3 text-sm mt-3">
                <p>
                  <strong>Your cooperation helps keep cabin rates low for all members.</strong>
                </p>
              </div>
            </div>
          </details>
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
      # Validate availability immediately
      |> validate_dates()
      |> calculate_price_if_ready()
      |> then(fn s ->
        update_url_with_search_params(
          s,
          s.assigns.checkin_date,
          s.assigns.checkout_date,
          s.assigns.guests_count,
          s.assigns.children_count,
          :room
        )
      end)

    {:noreply, socket}
  end

  def handle_event("booking-mode-changed", %{"booking_mode" => "buyout"}, socket) do
    # Prevent switching to buyout if not allowed
    if can_select_booking_mode?(socket, socket.assigns.checkin_date) do
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
        # Validate availability immediately
        |> validate_dates()
        |> calculate_price_if_ready()
        |> then(fn s ->
          update_url_with_search_params(
            s,
            s.assigns.checkin_date,
            s.assigns.checkout_date,
            s.assigns.guests_count,
            s.assigns.children_count,
            :buyout
          )
        end)

      {:noreply, socket}
    else
      # Mode not allowed: ignore buyout selection and keep room mode
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

    # Check if this is a deselection attempt (clicking an already selected room)
    current_selected_id = socket.assigns.selected_room_id
    current_selected_ids = socket.assigns.selected_room_ids || []
    is_deselection = room_id == current_selected_id || room_id in current_selected_ids

    # Check if room is available before allowing selection (but allow deselection)
    room = Enum.find(socket.assigns.available_rooms || [], &(&1.id == room_id))

    {availability, _reason} =
      if room,
        do: room.availability_status || {:available, nil},
        else: {:unavailable, "Room not found"}

    # Prevent selection of unavailable rooms, but allow deselection
    if availability == :unavailable && !is_deselection do
      {:noreply, socket}
    else
      # Determine if this is a checkbox toggle (family members) or radio selection
      if can_select_multiple_rooms?(socket.assigns) do
        # Checkbox: toggle the room in the selected list
        current_ids = socket.assigns.selected_room_ids || []
        room_id_to_toggle = room_id
        guests_count = parse_guests_count(socket.assigns.guests_count) || 1

        selected_room_ids =
          if room_id_to_toggle in current_ids do
            # Uncheck: remove from list
            List.delete(current_ids, room_id_to_toggle)
          else
            # Check: add to list (but respect max limit and minimum guests requirement)
            max_rooms = max_rooms_for_user(socket.assigns)

            # Prevent selecting multiple rooms when only 1 person total (adults + children) is selected
            children_count = parse_children_count(socket.assigns.children_count) || 0
            total_people = guests_count + children_count

            if total_people == 1 && length(current_ids) > 0 do
              # Can't add a second room with only 1 person total
              current_ids
            else
              if length(current_ids) < max_rooms do
                [room_id_to_toggle | current_ids]
              else
                current_ids
              end
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
          |> validate_guest_capacity()
          |> update_available_rooms()
          |> calculate_price_if_ready()

        {:noreply, socket}
      else
        # Radio button: single selection
        # Allow deselection by clicking the same room again
        current_selected_id = socket.assigns.selected_room_id
        new_selected_id = if room_id == current_selected_id, do: nil, else: room_id

        socket =
          socket
          |> assign(
            selected_room_id: new_selected_id,
            selected_room_ids: if(new_selected_id, do: [new_selected_id], else: []),
            calculated_price: nil,
            price_error: nil
          )
          |> validate_guest_capacity()
          |> update_available_rooms()
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
      |> validate_guest_capacity()
      |> update_available_rooms()
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
      |> validate_guest_capacity()
      |> update_url_with_search_params(
        socket.assigns.checkin_date,
        socket.assigns.checkout_date,
        new_count,
        socket.assigns.children_count,
        socket.assigns.selected_booking_mode
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
      |> validate_guest_capacity()
      |> update_url_with_search_params(
        socket.assigns.checkin_date,
        socket.assigns.checkout_date,
        new_count,
        socket.assigns.children_count,
        socket.assigns.selected_booking_mode
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
      |> validate_guest_capacity()
      |> update_url_with_search_params(
        socket.assigns.checkin_date,
        socket.assigns.checkout_date,
        socket.assigns.guests_count,
        new_count,
        socket.assigns.selected_booking_mode
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
      |> validate_guest_capacity()
      |> update_url_with_search_params(
        socket.assigns.checkin_date,
        socket.assigns.checkout_date,
        socket.assigns.guests_count,
        new_count,
        socket.assigns.selected_booking_mode
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
      |> validate_guest_capacity()
      |> update_available_rooms()
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  def handle_event("children-changed", %{"children_count" => children_str}, socket) do
    children_count = parse_integer(children_str) || 0

    socket =
      socket
      |> assign(children_count: children_count, calculated_price: nil, price_error: nil)
      |> validate_guest_capacity()
      |> update_available_rooms()
      |> calculate_price_if_ready()

    {:noreply, socket}
  end

  # Fallback handlers for cursor-move and cursor-leave events
  # These events are handled by the DateRangePicker component, but we add
  # these handlers as a safety measure in case events reach the parent LiveView
  def handle_event("cursor-move", _date_str, socket) do
    # These events should be handled by the DateRangePicker component
    # Ignore them here to prevent crashes
    {:noreply, socket}
  end

  def handle_event("cursor-leave", _params, socket) do
    # These events should be handled by the DateRangePicker component
    # Ignore them here to prevent crashes
    {:noreply, socket}
  end

  def handle_event("create-booking", _params, socket) do
    case validate_and_create_booking(socket) do
      {:ok, booking} ->
        # Redirect to checkout page for payment
        {:noreply,
         socket
         |> put_flash(:info, "Booking created! Please complete payment to confirm.")
         |> push_navigate(to: ~p"/bookings/checkout/#{booking.id}")}

      {:error, :insufficient_capacity} ->
        {:noreply,
         socket
         |> put_flash(:error, "Sorry, there is not enough capacity for your requested dates.")
         |> assign(
           form_errors: %{
             general: "Sorry, there is not enough capacity for your requested dates."
           },
           calculated_price: nil,
           price_error: "Insufficient capacity"
         )}

      {:error, :property_unavailable} ->
        {:noreply,
         socket
         |> put_flash(:error, "Sorry, the property is not available for your requested dates.")
         |> assign(
           form_errors: %{
             general: "Sorry, the property is not available for your requested dates."
           },
           calculated_price: nil,
           price_error: "Property unavailable"
         )}

      {:error, :rooms_already_booked} ->
        {:noreply,
         socket
         |> put_flash(:error, "Sorry, some rooms are already booked for your requested dates.")
         |> assign(
           form_errors: %{
             general: "Sorry, some rooms are already booked for your requested dates."
           },
           calculated_price: nil,
           price_error: "Rooms unavailable"
         )}

      {:error, :room_unavailable} ->
        # Map room_unavailable to rooms_already_booked for consistent error handling
        {:noreply,
         socket
         |> put_flash(:error, "Sorry, some rooms are already booked for your requested dates.")
         |> assign(
           form_errors: %{
             general: "Sorry, some rooms are already booked for your requested dates."
           },
           calculated_price: nil,
           price_error: "Rooms unavailable"
         )}

      {:error, :stale_inventory} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "The availability changed while you were booking. Please refresh the calendar and try again."
         )
         |> assign(
           form_errors: %{
             general:
               "The availability changed while you were booking. Please refresh the calendar and try again."
           },
           calculated_price: nil,
           price_error: "Availability changed"
         )}

      {:error, :invalid_parameters} ->
        {:noreply,
         socket
         |> put_flash(:error, "Please fill in all required fields.")
         |> assign(
           form_errors: %{general: "Please fill in all required fields."},
           calculated_price: nil,
           price_error: "Invalid parameters"
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

      {:error, _reason} ->
        # Handle any other error atoms that weren't explicitly handled above
        {:noreply,
         socket
         |> put_flash(:error, "An error occurred while creating your booking. Please try again.")
         |> assign(
           form_errors: %{
             general: "An error occurred while creating your booking. Please try again."
           },
           calculated_price: nil,
           price_error: "Booking failed"
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
          socket.assigns.children_count,
          active_tab,
          socket.assigns.selected_booking_mode
        )

      socket =
        socket
        |> assign(active_tab: active_tab)
        |> push_patch(to: ~p"/bookings/tahoe?#{URI.encode_query(query_params)}")

      {:noreply, socket}
    else
      {:noreply, socket}
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
      Logger.info(
        "[TahoeBookingLive] update_available_rooms called. " <>
          "Check-in: #{socket.assigns.checkin_date}, " <>
          "Check-out: #{socket.assigns.checkout_date}, " <>
          "Property: #{socket.assigns.property}"
      )

      # Ensure valid guest/children counts for filtering
      # Get values from assigns with fallback, then parse to ensure valid integers
      raw_guests = Map.get(socket.assigns, :guests_count, 1)
      raw_children = Map.get(socket.assigns, :children_count, 0)

      # Parse and validate - these functions always return valid integers
      guests_count = parse_guests_count(raw_guests)
      children_count = parse_children_count(raw_children)

      Logger.info(
        "[TahoeBookingLive] Guest counts - Raw: guests=#{inspect(raw_guests)}, children=#{inspect(raw_children)}. " <>
          "Parsed: guests=#{guests_count}, children=#{children_count}"
      )

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
      # Preload images for all rooms
      all_rooms =
        from(r in Room,
          where: r.property == ^socket.assigns.property,
          order_by: [asc: r.property, asc: r.name],
          preload: [:room_category, :image]
        )
        |> Repo.all()

      Logger.info(
        "[TahoeBookingLive] Found #{length(all_rooms)} rooms for property #{socket.assigns.property}"
      )

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

      # Calculate total capacity of already selected rooms
      selected_room_ids = socket.assigns.selected_room_ids || []

      total_selected_capacity =
        selected_room_ids
        |> Enum.map(fn room_id ->
          case Enum.find(all_rooms, &(&1.id == room_id)) do
            nil -> 0
            selected_room -> selected_room.capacity_max
          end
        end)
        |> Enum.sum()

      rooms_with_status =
        all_rooms
        |> Enum.map(fn room ->
          # Determine availability status and reason
          is_available = MapSet.member?(available_room_ids, room.id)
          is_active = room.is_active
          room_already_selected = room.id in selected_room_ids

          # Check capacity based on selection mode
          capacity_ok =
            if can_select_multiple do
              # Multiple room selection: guests can be spread across multiple rooms
              if room_already_selected do
                # If room is already selected, allow it (user can unselect it)
                true
              else
                # Room is not selected yet
                if total_selected_capacity == 0 do
                  # First room selection: allow any room (guests can be spread across multiple rooms)
                  true
                else
                  # Subsequent room selection: check if adding it would satisfy total capacity
                  # Total capacity after adding this room must be >= total_people
                  total_selected_capacity + room.capacity_max >= total_people
                end
              end
            else
              # Single room selection: capacity must accommodate all guests
              if total_people > 0, do: room.capacity_max >= total_people, else: true
            end

          # Check if trying to add second room with only 1 person total (adults + children)
          guests_count = parse_guests_count(socket.assigns.guests_count) || 1
          children_count = parse_children_count(socket.assigns.children_count) || 0
          total_people = guests_count + children_count
          only_one_person = total_people == 1

          trying_to_add_second_room =
            can_select_multiple && length(selected_room_ids) > 0 && not room_already_selected

          # Check if user has already selected a room and can't select multiple
          # This applies to both single membership users and family/lifetime members with existing bookings
          cannot_select_another_room =
            not can_select_multiple &&
              length(selected_room_ids) > 0 &&
              not room_already_selected

          # Check if user has an existing booking (for better error message)
          has_existing_booking =
            if socket.assigns[:active_bookings] do
              active_bookings = socket.assigns[:active_bookings] || []
              count_rooms_in_active_bookings(active_bookings) > 0
            else
              false
            end

          # Determine membership type for error message
          membership_type = socket.assigns[:membership_type] || :none

          availability_status =
            cond do
              not is_active ->
                {:unavailable, "Room is not active"}

              not is_available ->
                {:unavailable, "Already booked for selected dates"}

              cannot_select_another_room ->
                error_message =
                  if has_existing_booking && membership_type in [:family, :lifetime] do
                    "You already have a room reserved. You can only select one room for your second booking. Please deselect the current room to select a different one."
                  else
                    "Single membership allows only one room per booking. Please deselect the current room to select a different one."
                  end

                {:unavailable, error_message}

              only_one_person && trying_to_add_second_room ->
                {:unavailable,
                 "Cannot book multiple rooms with only 1 person. Please select more guests to book additional rooms."}

              not capacity_ok ->
                if can_select_multiple do
                  {:unavailable,
                   "Adding this room would not provide enough total capacity. Selected rooms: #{total_selected_capacity} guests, need #{total_people} total. This room: #{room.capacity_max} guests."}
                else
                  {:unavailable,
                   "Room capacity (#{room.capacity_max}) is less than number of guests (#{total_people})"}
                end

              true ->
                {:available, nil}
            end

          Map.put(room, :availability_status, availability_status)
        end)
        |> Enum.map(fn room ->
          # Load pricing from database for display
          # Get adult price per person per night
          adult_price =
            if socket.assigns.checkin_date do
              season =
                Season.find_season_for_date(socket.assigns.seasons, socket.assigns.checkin_date)

              season_id = if season, do: season.id, else: nil

              # Try room-specific pricing first, then fall back to category pricing
              # Fall back to category-based pricing if no room-specific rule
              pricing_rule =
                PricingRule.find_most_specific(
                  socket.assigns.property,
                  season_id,
                  room.id,
                  # Don't pass category_id when checking room-specific
                  nil,
                  :room,
                  :per_person_per_night
                ) ||
                  PricingRule.find_most_specific(
                    socket.assigns.property,
                    season_id,
                    # No room_id for category lookup
                    nil,
                    room.room_category_id,
                    :room,
                    :per_person_per_night
                  )

              if pricing_rule && pricing_rule.amount do
                pricing_rule.amount
              else
                # Fallback to default if no pricing rule found
                Money.new(45, :USD)
              end
            else
              # Fallback if no checkin date
              Money.new(45, :USD)
            end

          # Look up children pricing using same hierarchy as adult pricing
          # Falls back to $25 if no children pricing rule found
          children_price =
            if socket.assigns.checkin_date do
              season =
                Season.find_season_for_date(socket.assigns.seasons, socket.assigns.checkin_date)

              season_id = if season, do: season.id, else: nil

              children_pricing_rule =
                PricingRule.find_children_pricing_rule(
                  socket.assigns.property,
                  season_id,
                  room.id,
                  nil,
                  :room,
                  :per_person_per_night
                ) ||
                  PricingRule.find_children_pricing_rule(
                    socket.assigns.property,
                    season_id,
                    nil,
                    room.room_category_id,
                    :room,
                    :per_person_per_night
                  ) ||
                  PricingRule.find_children_pricing_rule(
                    socket.assigns.property,
                    season_id,
                    nil,
                    nil,
                    :room,
                    :per_person_per_night
                  )

              if children_pricing_rule && children_pricing_rule.children_amount do
                children_pricing_rule.children_amount
              else
                # Fallback to $25 if no children pricing rule found
                Money.new(25, :USD)
              end
            else
              # Fallback if no checkin date
              Money.new(25, :USD)
            end

          # Calculate minimum price if room has min_billable_occupancy > 1
          min_occupancy = room.min_billable_occupancy || 1

          minimum_price =
            if min_occupancy > 1 do
              # Calculate minimum price: adult_price * min_occupancy
              case Money.mult(adult_price, min_occupancy) do
                {:ok, total} -> total
                {:error, _} -> adult_price
              end
            else
              nil
            end

          room
          |> Map.put(:adult_price_per_night, adult_price)
          |> Map.put(:children_price_per_night, children_price)
          |> Map.put(:minimum_price, minimum_price)
          |> Map.put(:min_billable_occupancy, min_occupancy)
        end)

      assign(socket, available_rooms: rooms_with_status)
    else
      assign(socket, available_rooms: [])
    end
  end

  defp calculate_price_if_ready(socket) do
    PricingHelpers.calculate_price_if_ready(socket, :tahoe,
      parse_guests_fn: &parse_guests_count/1,
      parse_children_fn: &parse_children_count/1,
      can_select_multiple_rooms_fn: &can_select_multiple_rooms?/1
    )
  end

  # Helper function that works with seasons and checkin_date (for template usage)
  defp can_select_booking_mode?(seasons, checkin_date) when is_list(seasons) do
    # Check if pricing rules allow buyout mode for the selected date's season
    if checkin_date do
      season = Season.find_season_for_date(seasons, checkin_date)
      season_id = if season, do: season.id, else: nil

      pricing_rule =
        PricingRule.find_most_specific(
          :tahoe,
          season_id,
          nil,
          nil,
          :buyout,
          :buyout_fixed
        )

      !is_nil(pricing_rule)
    else
      false
    end
  end

  # Helper function that works with socket (for code usage)
  defp can_select_booking_mode?(socket, checkin_date) when is_struct(socket) do
    can_select_booking_mode?(socket.assigns.seasons, checkin_date)
  end

  defp can_submit_booking?(
         booking_mode,
         checkin_date,
         checkout_date,
         room_ids_or_id,
         capacity_error,
         price_error,
         form_errors,
         date_validation_errors
       ) do
    has_rooms? =
      case room_ids_or_id do
        room_id when is_binary(room_id) -> not is_nil(room_id)
        room_ids when is_list(room_ids) -> length(room_ids) > 0
        _ -> false
      end

    has_errors? =
      (capacity_error && capacity_error != "") ||
        (price_error && price_error != "") ||
        (form_errors && map_size(form_errors) > 0) ||
        (date_validation_errors && map_size(date_validation_errors) > 0)

    checkin_date && checkout_date &&
      (booking_mode == :buyout || (booking_mode == :room && has_rooms?)) &&
      !has_errors?
  end

  defp validate_and_create_booking(socket) do
    property = socket.assigns.property
    checkin_date = socket.assigns.checkin_date
    checkout_date = socket.assigns.checkout_date
    booking_mode = socket.assigns.selected_booking_mode
    guests_count = socket.assigns.guests_count
    children_count = socket.assigns.children_count || 0
    user_id = socket.assigns.user.id

    # Validate required fields
    if is_nil(checkin_date) || is_nil(checkout_date) || is_nil(guests_count) || guests_count <= 0 do
      {:error, :invalid_parameters}
    else
      case booking_mode do
        :buyout ->
          # Use BookingLocker for buyout booking with inventory locking
          BookingLocker.create_buyout_booking(
            user_id,
            property,
            checkin_date,
            checkout_date,
            guests_count
          )

        :room ->
          # Determine which rooms to book
          room_ids =
            if can_select_multiple_rooms?(socket.assigns) do
              socket.assigns.selected_room_ids
            else
              if socket.assigns.selected_room_id, do: [socket.assigns.selected_room_id], else: []
            end

          if room_ids == [] do
            {:error, :invalid_parameters}
          else
            # Create room bookings using BookingLocker
            # For multiple rooms, create them sequentially and return the first one for checkout
            create_room_bookings_with_locking(
              user_id,
              property,
              checkin_date,
              checkout_date,
              guests_count,
              children_count,
              room_ids
            )
          end

        _ ->
          {:error, :invalid_booking_mode}
      end
    end
  end

  defp create_room_bookings_with_locking(
         user_id,
         _property,
         checkin_date,
         checkout_date,
         guests_count,
         children_count,
         room_ids
       ) do
    # Create a single booking with all rooms using BookingLocker
    # This ensures proper inventory locking for all rooms atomically
    case BookingLocker.create_room_booking(
           user_id,
           room_ids,
           checkin_date,
           checkout_date,
           guests_count,
           children_count: children_count
         ) do
      {:ok, booking} ->
        {:ok, booking}

      {:error, :room_unavailable} ->
        {:error, :rooms_already_booked}

      {:error, :stale_inventory} ->
        {:error, :stale_inventory}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      if is_binary(msg) do
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      else
        to_string(msg)
      end
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
      "room" -> :room
      # Default handled by resolve logic or socket default
      _ -> nil
    end
  end

  defp update_url_with_dates(socket, checkin_date, checkout_date) do
    guests_count = socket.assigns.guests_count || 1
    children_count = socket.assigns.children_count || 0
    active_tab = socket.assigns.active_tab || :booking
    booking_mode = socket.assigns.selected_booking_mode || :room

    query_params =
      build_query_params(
        checkin_date,
        checkout_date,
        guests_count,
        children_count,
        active_tab,
        booking_mode
      )

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
         children_count,
         booking_mode
       ) do
    active_tab = socket.assigns.active_tab || :booking

    query_params =
      build_query_params(
        checkin_date,
        checkout_date,
        guests_count,
        children_count,
        active_tab,
        booking_mode
      )

    if map_size(query_params) > 0 do
      push_patch(socket, to: ~p"/bookings/tahoe?#{URI.encode_query(query_params)}")
    else
      push_patch(socket, to: ~p"/bookings/tahoe")
    end
  end

  defp build_query_params(
         checkin_date,
         checkout_date,
         guests_count,
         children_count,
         active_tab,
         booking_mode
       ) do
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
        # Always include guests_count in URL, even if it's the default value of 1
        Map.put(params, "guests_count", Integer.to_string(guests_count))
      else
        params
      end

    params =
      if children_count && children_count >= 0 do
        # Always include children_count in URL, even if it's 0
        Map.put(params, "children_count", Integer.to_string(children_count))
      else
        params
      end

    params =
      if active_tab && active_tab != :booking do
        Map.put(params, "tab", Atom.to_string(active_tab))
      else
        params
      end

    params =
      if booking_mode && booking_mode != :room do
        Map.put(params, "booking_mode", Atom.to_string(booking_mode))
      else
        params
      end

    params
  end

  # Real-time validation functions

  # Enforces booking mode rules based on pricing availability
  defp enforce_season_booking_mode(socket) do
    checkin_date = socket.assigns.checkin_date
    booking_mode = socket.assigns.selected_booking_mode

    if checkin_date && booking_mode == :buyout do
      if !can_select_booking_mode?(socket.assigns.seasons, checkin_date) do
        # Force booking mode to room if buyout not allowed
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
        |> validate_season_date_range(socket)
        |> validate_advance_booking_limit(
          socket.assigns.checkin_date,
          socket.assigns.checkout_date
        )
        |> validate_weekend_rule(socket.assigns.checkin_date, socket.assigns.checkout_date)
        |> validate_max_nights(socket.assigns.checkin_date, socket.assigns.checkout_date)
        |> validate_season_booking_mode(socket)
        |> validate_buyout_availability(socket)
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

  defp validate_season_date_range(errors, _socket) do
    # validate_season_date_range always returns empty map (cross-season bookings allowed)
    # No validation needed here
    errors
  end

  defp validate_advance_booking_limit(errors, checkin_date, checkout_date) do
    validation_errors =
      SeasonHelpers.validate_advance_booking_limit(:tahoe, checkin_date, checkout_date)

    if Map.has_key?(validation_errors, :advance_booking_limit) do
      Map.put(errors, :advance_booking_limit, validation_errors.advance_booking_limit)
    else
      errors
    end
  end

  defp validate_season_booking_mode(errors, socket) do
    if socket.assigns.checkin_date && socket.assigns.selected_booking_mode == :buyout do
      if !can_select_booking_mode?(socket.assigns.seasons, socket.assigns.checkin_date) do
        Map.put(
          errors,
          :season_booking_mode,
          "Full buyout is not available for the selected dates"
        )
      else
        errors
      end
    else
      errors
    end
  end

  defp validate_buyout_availability(errors, socket) do
    if socket.assigns.selected_booking_mode == :buyout && socket.assigns.checkin_date &&
         socket.assigns.checkout_date do
      checkin = socket.assigns.checkin_date
      checkout = socket.assigns.checkout_date

      # 1. Check for blackouts
      # has_blackout? uses inclusive overlap, which is safer for availability checks
      if Bookings.has_blackout?(:tahoe, checkin, checkout) do
        Map.put(
          errors,
          :availability,
          "Selected dates are not available due to blackout dates."
        )
      else
        # 2. Check for ANY existing active bookings (rooms or buyouts)
        # list_bookings returns potentially overlapping bookings (inclusive)
        # We filter for status and strict overlap to be precise
        overlaps = Bookings.list_bookings(:tahoe, checkin, checkout)

        has_conflict =
          Enum.any?(overlaps, fn booking ->
            booking.status in [:hold, :complete] &&
              Bookings.bookings_overlap?(
                checkin,
                checkout,
                booking.checkin_date,
                booking.checkout_date
              )
          end)

        if has_conflict do
          Map.put(
            errors,
            :availability,
            "Selected dates are not available due to existing bookings."
          )
        else
          errors
        end
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

    # Get max nights from season for check-in date
    max_nights =
      if checkin_date do
        season = Ysc.Bookings.Season.for_date(:tahoe, checkin_date)
        Ysc.Bookings.Season.get_max_nights(season, :tahoe)
      else
        # Fallback to Tahoe default
        4
      end

    if nights > max_nights do
      Map.put(errors, :max_nights, "Maximum #{max_nights} nights allowed per booking")
    else
      errors
    end
  end

  defp validate_active_booking(socket) do
    errors = socket.assigns.date_validation_errors || %{}

    if socket.assigns.checkin_date && socket.assigns.checkout_date && socket.assigns.user do
      user = socket.assigns.user

      user_with_subs =
        case user.subscriptions do
          %Ecto.Association.NotLoaded{} ->
            Accounts.get_user!(user.id) |> Repo.preload(:subscriptions)

          _ ->
            user
        end

      membership_type = get_membership_type(user_with_subs)

      # For family/lifetime members, check room count instead of just booking existence
      if membership_type in [:family, :lifetime] do
        user_id = user.id

        # Count rooms in overlapping bookings
        overlapping_query =
          from b in Booking,
            join: br in "booking_rooms",
            on: br.booking_id == b.id,
            where: b.user_id == ^user_id,
            where: b.property == :tahoe,
            where: b.status in [:complete],
            where:
              fragment(
                "? < ? AND ? > ?",
                b.checkin_date,
                ^socket.assigns.checkout_date,
                b.checkout_date,
                ^socket.assigns.checkin_date
              )

        room_count_query =
          from br in "booking_rooms",
            join: b in subquery(overlapping_query),
            on: br.booking_id == b.id,
            select: count(br.id)

        existing_room_count = Repo.one(room_count_query) || 0

        if existing_room_count >= 2 do
          Map.put(
            errors,
            :active_booking,
            "You have reached the maximum of 2 rooms for your #{String.capitalize("#{membership_type}")} membership in this time period."
          )
        else
          errors
        end
      else
        # Single membership: only one booking at a time
        user_id = user.id

        overlapping_query =
          from b in Booking,
            where: b.user_id == ^user_id,
            where: b.property == :tahoe,
            where: b.status in [:complete],
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
            "You can only have one active reservation at a time. Please complete your existing reservation first."
          )
        else
          errors
        end
      end
    else
      errors
    end
  end

  defp check_booking_eligibility(user, active_bookings)

  defp check_booking_eligibility(nil, _active_bookings) do
    sign_in_path = ~p"/users/log-in"

    sign_in_link =
      ~s(<a href="#{sign_in_path}" class="font-semibold text-amber-900 hover:text-amber-950 underline">sign in</a>)

    {
      false,
      "Sign In Required",
      "You must be signed in to make a booking. Please #{sign_in_link} to continue."
    }
  end

  defp check_booking_eligibility(user, active_bookings) do
    # Check if user account is approved
    if user.state != :active do
      {
        false,
        "Membership Pending Approval",
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
        # Check if user has an active booking (use provided active_bookings if available)
        active_bookings_list = active_bookings || get_active_bookings(user.id)

        # Get membership type to check if user can have multiple bookings
        membership_type = get_membership_type(user_with_subs)

        # For family/lifetime members, check room count instead of just booking existence
        if membership_type in [:family, :lifetime] do
          # Count total rooms in active bookings
          total_rooms = count_rooms_in_active_bookings(active_bookings_list)

          if total_rooms >= 2 do
            # User has 2 rooms already, check if any booking is still active
            # Get the latest checkout date from all active bookings
            latest_checkout_date = get_latest_checkout_date(active_bookings_list)

            if latest_checkout_date do
              today = Date.utc_today()

              # Check if booking is still active
              if Date.compare(latest_checkout_date, today) == :gt or
                   (Date.compare(latest_checkout_date, today) == :eq and not past_checkout_time?()) do
                formatted_date = format_date(latest_checkout_date)

                {
                  false,
                  "Maximum rooms reached",
                  "You have reached the maximum of 2 rooms for your #{String.capitalize("#{membership_type}")} membership. You can make a new reservation once your current stay is complete (after #{formatted_date}) or if you cancel your existing booking."
                }
              else
                {true, nil, nil}
              end
            else
              {true, nil, nil}
            end
          else
            # User has less than 2 rooms, allow booking (validation will ensure dates overlap)
            {true, nil, nil}
          end
        else
          # Single membership: only one booking at a time
          case get_active_booking(user.id, active_bookings_list) do
            nil ->
              {true, nil, nil}

            active_booking ->
              checkout_date = active_booking.checkout_date
              today = Date.utc_today()

              # Check if booking is still active (checkout date is in the future, or today but checkout time hasn't passed)
              if Date.compare(checkout_date, today) == :gt or
                   (Date.compare(checkout_date, today) == :eq and not past_checkout_time?()) do
                formatted_date = format_date(checkout_date)

                {
                  false,
                  "Looks like you already have a booking!",
                  "You can make a new reservation once your current stay is complete (after #{formatted_date}) or if you cancel your existing one."
                }
              else
                {true, nil, nil}
              end
          end
        end
      else
        {
          false,
          "Membership Required",
          "You need an active membership to make bookings. Please activate or renew your membership to continue."
        }
      end
    end
  end

  defp get_active_booking(user_id, active_bookings) do
    bookings = active_bookings || get_active_bookings(user_id)
    List.first(bookings)
  end

  defp get_latest_checkout_date(active_bookings) do
    case active_bookings do
      [] ->
        nil

      bookings when is_list(bookings) ->
        bookings
        |> Enum.max_by(& &1.checkout_date, Date)

      _ ->
        nil
    end
    |> case do
      nil -> nil
      booking -> booking.checkout_date
    end
  end

  defp get_active_bookings(user_id, limit \\ 10) do
    today = Date.utc_today()
    checkout_time = ~T[11:00:00]

    query =
      from b in Booking,
        where: b.user_id == ^user_id,
        where: b.property == :tahoe,
        where: b.status == :complete,
        where: b.checkout_date >= ^today,
        order_by: [asc: b.checkin_date],
        limit: ^limit,
        preload: [:rooms]

    bookings = Repo.all(query)

    # Filter out bookings that are past checkout time today
    bookings
    |> Enum.filter(fn booking ->
      if Date.compare(booking.checkout_date, today) == :eq do
        now = DateTime.utc_now()
        checkout_datetime = DateTime.new!(today, checkout_time, "Etc/UTC")
        DateTime.compare(now, checkout_datetime) == :lt
      else
        true
      end
    end)
    |> Enum.take(limit)
  end

  defp past_checkout_time? do
    today = Date.utc_today()
    checkout_time = ~T[11:00:00]
    checkout_datetime = DateTime.new!(today, checkout_time, "Etc/UTC")
    now = DateTime.utc_now()
    DateTime.compare(now, checkout_datetime) == :gt
  end

  defp get_membership_type(user) do
    # Check for lifetime membership first
    if Accounts.has_lifetime_membership?(user) do
      :lifetime
    else
      # Get active subscriptions
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
    subscription = Repo.preload(subscription, :subscription_items)

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
      subscription = Repo.preload(subscription, :subscription_items)

      case subscription.subscription_items do
        [item | _] -> Map.get(price_to_amount, item.stripe_price_id, 0)
        _ -> 0
      end
    end)
  end

  defp count_rooms_in_active_bookings(active_bookings) do
    active_bookings
    |> Enum.map(fn booking ->
      # Rooms are preloaded, count them
      case booking.rooms do
        %Ecto.Association.NotLoaded{} -> 0
        rooms when is_list(rooms) -> length(rooms)
        _ -> 0
      end
    end)
    |> Enum.sum()
  end

  defp dates_are_restricted?(restricted_min, restricted_max, default_min, default_max) do
    # Dates are restricted if they differ from the default range
    Date.compare(restricted_min, default_min) != :eq ||
      Date.compare(restricted_max, default_max) != :eq
  end

  defp calculate_restricted_date_range(active_bookings, max_booking_date) do
    # Get the first active booking (should only be one for this use case)
    case List.first(active_bookings) do
      nil ->
        # No active bookings, use default range
        {Date.utc_today(), max_booking_date}

      booking ->
        existing_checkin = booking.checkin_date
        existing_checkout = booking.checkout_date
        existing_nights = Date.diff(existing_checkout, existing_checkin)
        max_nights = 4

        if existing_nights >= max_nights do
          # Booking is already 4 days, restrict to those exact dates (no extension)
          {existing_checkin, existing_checkout}
        else
          # Calculate how many nights to add in each direction
          # If existing is 1 night, extend 3 days backward and forward
          # If existing is 2 nights, extend 2 days backward and forward
          # If existing is 3 nights, extend 1 day backward and forward
          nights_to_add = max_nights - existing_nights

          # Extend backward from check-in date
          restricted_min = Date.add(existing_checkin, -nights_to_add)

          # Extend forward: maximum checkout is 4 nights from check-in
          restricted_max = Date.add(existing_checkin, max_nights)

          # Ensure we don't go before today or after max_booking_date
          today = Date.utc_today()

          restricted_min =
            if Date.compare(restricted_min, today) == :lt, do: today, else: restricted_min

          restricted_max =
            if Date.compare(restricted_max, max_booking_date) == :gt,
              do: max_booking_date,
              else: restricted_max

          {restricted_min, restricted_max}
        end
    end
  end

  defp format_date(date) do
    Calendar.strftime(date, "%B %d, %Y")
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

    # Family/lifetime members can select multiple rooms only if they don't already have a booking
    # If they have 1 room booking, they can only select 1 room for their second booking
    if membership_type in [:family, :lifetime] do
      active_bookings = assigns[:active_bookings] || []
      total_rooms = count_rooms_in_active_bookings(active_bookings)
      # Can select multiple rooms only if they have 0 rooms (no existing booking)
      total_rooms == 0
    else
      false
    end
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

    # Check if user already has a booking (for assigns map only)
    existing_rooms =
      if is_map(user_or_assigns) && Map.has_key?(user_or_assigns, :active_bookings) do
        active_bookings = user_or_assigns[:active_bookings] || []
        count_rooms_in_active_bookings(active_bookings)
      else
        0
      end

    # If user already has 1 room booking, they can only book 1 more room
    # Otherwise, family/lifetime members can book up to 2 rooms
    case membership_type do
      :family ->
        if existing_rooms >= 1 do
          1
        else
          2
        end

      :lifetime ->
        if existing_rooms >= 1 do
          1
        else
          2
        end

      _ ->
        1
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

  defp validate_guest_capacity(socket) do
    # Only validate if rooms are selected and we're in room booking mode
    if socket.assigns.selected_booking_mode == :room &&
         (socket.assigns.selected_room_id ||
            (socket.assigns.selected_room_ids && length(socket.assigns.selected_room_ids) > 0)) do
      guests_count = parse_guests_count(socket.assigns.guests_count) || 1
      children_count = parse_children_count(socket.assigns.children_count) || 0
      total_guests = guests_count + children_count

      # Get selected room IDs
      selected_room_ids =
        if can_select_multiple_rooms?(socket.assigns) do
          socket.assigns.selected_room_ids || []
        else
          if socket.assigns.selected_room_id, do: [socket.assigns.selected_room_id], else: []
        end

      if length(selected_room_ids) > 0 do
        # Calculate total capacity of selected rooms
        all_rooms = Bookings.list_rooms(socket.assigns.property)

        total_capacity =
          selected_room_ids
          |> Enum.map(fn room_id ->
            case Enum.find(all_rooms, &(&1.id == room_id)) do
              nil -> 0
              room -> room.capacity_max
            end
          end)
          |> Enum.sum()

        if total_guests > total_capacity do
          assign(socket,
            capacity_error:
              "Total number of guests (#{total_guests}) exceeds the combined capacity of selected rooms (#{total_capacity} guests). Please select more rooms or reduce the number of guests."
          )
        else
          assign(socket, capacity_error: nil)
        end
      else
        assign(socket, capacity_error: nil)
      end
    else
      assign(socket, capacity_error: nil)
    end
  end

  # Refund policy formatting helpers
  defp format_refund_rule(rule) do
    refund_percentage = Decimal.to_float(rule.refund_percentage)
    forfeit_percentage = 100 - refund_percentage

    # If there's a custom description, use it (will be rendered as plain text)
    if rule.description && rule.description != "" do
      rule.description
    else
      # Otherwise, format based on days and percentage (includes HTML for styling)
      days = rule.days_before_checkin

      cond do
        forfeit_percentage == 0 ->
          "Cancel #{days} or more days before arrival → <strong>Full refund</strong>"

        forfeit_percentage == 100 ->
          "Cancel less than #{days} days before arrival → <strong>100% forfeited</strong>"

        true ->
          "Cancel less than #{days} days before arrival → <strong>#{forfeit_percentage |> round()}% forfeited</strong>"
      end
    end
  end

  # Bed icon SVG helpers
  defp bed_icon_svg(bed_type, class)

  defp bed_icon_svg(:single, class) do
    """
    <svg class="#{class}" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" role="img" aria-labelledby="twinBedTitle">
      <path d="M6 9h12" />
      <rect x="6" y="9" width="12" height="8" rx="2" />
      <path d="M8 17v2m8-2v2" />
      <rect x="9.75" y="10.25" width="4.5" height="2.5" rx="1" />
    </svg>
    """
  end

  defp bed_icon_svg(:queen, class) do
    """
    <svg class="#{class}" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" role="img" aria-labelledby="queenBedTitle">
      <path d="M4 9h16" />
      <rect x="4" y="9" width="16" height="8" rx="2" />
      <path d="M7 17v2m10-2v2" />
      <rect x="7.5" y="10.25" width="5" height="2.5" rx="1" />
      <rect x="11.5" y="10.25" width="5" height="2.5" rx="1" />
    </svg>
    """
  end

  defp bed_icon_svg(:king, class) do
    """
    <svg class="#{class}" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" role="img" aria-labelledby="kingBedTitle">
      <path d="M3 9h18" />
      <rect x="3" y="9" width="18" height="8" rx="2" />
      <path d="M6 17v2m12-2v2" />
      <rect x="6.25" y="10.25" width="6" height="2.5" rx="1" />
      <rect x="11.75" y="10.25" width="6" height="2.5" rx="1" />
    </svg>
    """
  end

  # Room image helper functions
  defp get_room_blur_hash(nil), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"

  defp get_room_blur_hash(%Ysc.Media.Image{blur_hash: nil}),
    do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"

  defp get_room_blur_hash(%Ysc.Media.Image{blur_hash: blur_hash}), do: blur_hash

  defp get_room_image_url(nil), do: "/images/ysc_logo.png"

  defp get_room_image_url(%Ysc.Media.Image{} = image) do
    # Prefer thumbnail for room cards (smaller, faster loading)
    cond do
      not is_nil(image.thumbnail_path) -> image.thumbnail_path
      not is_nil(image.optimized_image_path) -> image.optimized_image_path
      not is_nil(image.raw_image_path) -> image.raw_image_path
      true -> "/images/ysc_logo.png"
    end
  end

  # Season caching helpers to avoid multiple database queries

  defp get_current_season_info_cached(seasons, today) do
    current_season = Season.find_season_for_date(seasons, today)

    if current_season do
      {season_start_date, season_end_date} =
        SeasonHelpers.get_season_date_range(current_season, today)

      {current_season, season_start_date, season_end_date}
    else
      {nil, nil, nil}
    end
  end

  defp calculate_max_booking_date_cached(seasons, today) do
    current_season = Season.find_season_for_date(seasons, today)

    if current_season do
      if current_season.advance_booking_days && current_season.advance_booking_days > 0 do
        # Current season has a limit - apply it
        Date.add(today, current_season.advance_booking_days)
      else
        # Current season has no limit - allow up to the end of current season
        {_season_start, season_end} = SeasonHelpers.get_season_date_range(current_season, today)

        # Also check if we can book into the next season (if it has a limit)
        next_season = get_next_season_cached(seasons, today, current_season)

        max_date = season_end

        if next_season && next_season.advance_booking_days &&
             next_season.advance_booking_days > 0 do
          # Next season has a limit - we can book up to that limit
          next_season_max = Date.add(today, next_season.advance_booking_days)
          # Use the later of: end of current season or next season's limit
          if Date.compare(next_season_max, max_date) == :gt do
            next_season_max
          else
            max_date
          end
        else
          max_date
        end
      end
    else
      # No current season found - use a conservative default
      Date.add(today, 365)
    end
  end

  defp get_next_season_cached(seasons, reference_date, current_season) do
    if current_season && length(seasons) > 1 do
      # Find the next season by calculating which one starts next
      next_seasons =
        seasons
        |> Enum.filter(fn season -> season.id != current_season.id end)
        |> Enum.map(fn season ->
          {season, get_next_season_occurrence_start(season, reference_date)}
        end)
        |> Enum.filter(fn {_season, start_date} -> start_date != nil end)
        |> Enum.sort_by(fn {_season, start_date} -> start_date end)

      case next_seasons do
        [{next_season, _start_date} | _] -> next_season
        _ -> nil
      end
    else
      nil
    end
  end

  # Gets the next occurrence start date for a season after the reference date
  defp get_next_season_occurrence_start(season, reference_date) do
    {ref_month, ref_day} = {reference_date.month, reference_date.day}
    {start_month, start_day} = {season.start_date.month, season.start_date.day}
    {end_month, end_day} = {season.end_date.month, season.end_date.day}

    cond do
      # If season spans years (e.g., Nov to Apr)
      start_month > end_month ->
        # If we're before the end date, next start could be this year or next
        if {ref_month, ref_day} <= {end_month, end_day} do
          # We're in the later part (Jan-Apr), next start is this year
          candidate = Date.new!(reference_date.year, start_month, start_day)

          if Date.compare(candidate, reference_date) == :gt,
            do: candidate,
            else: Date.new!(reference_date.year + 1, start_month, start_day)
        else
          # We're in the earlier part (Nov-Dec), next start is next year
          Date.new!(reference_date.year + 1, start_month, start_day)
        end

      # Same-year range
      {ref_month, ref_day} < {start_month, start_day} ->
        # Next start is this year
        Date.new!(reference_date.year, start_month, start_day)

      true ->
        # Next start is next year
        Date.new!(reference_date.year + 1, start_month, start_day)
    end
  end

  # Generate tooltips for unavailable dates
  # Returns a map of date strings (ISO format) to tooltip messages
  defp generate_date_tooltips(min_date, max_date, today, property, _seasons) do
    # Generate tooltips for a reasonable date range (3 months before min to 3 months after max)
    start_range = Date.add(min_date, -90)
    end_range = Date.add(max_date, 90)
    date_range = Date.range(start_range, end_range) |> Enum.to_list()

    # Get all rooms for the property
    all_rooms = Bookings.list_rooms(property) |> Enum.filter(& &1.is_active)

    # Get all bookings in the range (preload rooms for availability checking)
    bookings = Bookings.list_bookings(property, start_range, end_range, preload: [:rooms])

    # Get all blackouts in the range
    blackouts = Bookings.get_overlapping_blackouts(property, start_range, end_range)

    blackout_dates =
      blackouts
      |> Enum.flat_map(fn blackout ->
        Date.range(blackout.start_date, blackout.end_date) |> Enum.to_list()
      end)
      |> MapSet.new()

    # Get buyout dates from property inventory
    buyout_dates =
      from(pi in PropertyInventory,
        where: pi.property == ^property,
        where: pi.day >= ^start_range and pi.day <= ^end_range,
        where: pi.buyout_held == true or pi.buyout_booked == true,
        select: pi.day
      )
      |> Repo.all()
      |> MapSet.new()

    # Build tooltip map
    date_range
    |> Enum.reduce(%{}, fn date, acc ->
      tooltip =
        get_date_unavailability_reason(
          date,
          min_date,
          max_date,
          today,
          property,
          all_rooms,
          bookings,
          blackout_dates,
          buyout_dates
        )

      if tooltip do
        Map.put(acc, Date.to_iso8601(date), tooltip)
      else
        acc
      end
    end)
  end

  # Get the reason why a date is unavailable (returns nil if available)
  defp get_date_unavailability_reason(
         date,
         min_date,
         max_date,
         today,
         property,
         all_rooms,
         bookings,
         blackout_dates,
         buyout_dates
       ) do
    cond do
      # Past dates
      Date.compare(date, min_date) == :lt ->
        "Past dates cannot be booked"

      # Too far in future
      Date.compare(date, max_date) == :gt ->
        "Reservations are not open for this date yet"

      # Season restrictions (check if date is selectable based on season rules)
      not SeasonHelpers.is_date_selectable?(property, date, today) ->
        "Bookings for this season are not yet open"

      # Saturday check-in (Tahoe rule)
      Date.day_of_week(date) == 6 && property == :tahoe ->
        "Check-ins are not permitted on Saturdays"

      # Blackout
      MapSet.member?(blackout_dates, date) ->
        "This date is unavailable"

      # Buyout
      MapSet.member?(buyout_dates, date) ->
        "Full cabin buyout is already reserved on this date"

      # Check if all rooms are booked (for room booking mode)
      true ->
        # Check if all active rooms are booked for this date
        # We need to check if there's at least one room available for a single night stay
        date_available = check_date_availability_for_rooms(date, all_rooms, bookings)

        if not date_available do
          "All rooms are booked"
        else
          nil
        end
    end
  end

  # Check if at least one room is available for a specific date (as check-in date)
  defp check_date_availability_for_rooms(checkin_date, all_rooms, bookings) do
    if Enum.empty?(all_rooms) do
      false
    else
      # For tooltip purposes, we check if a single night stay is possible
      # (checkin_date to checkin_date + 1 day)
      checkout_date = Date.add(checkin_date, 1)

      # Filter bookings that overlap with this date range
      overlapping_bookings =
        Enum.filter(bookings, fn booking ->
          booking.status in [:hold, :complete] &&
            Bookings.bookings_overlap?(
              checkin_date,
              checkout_date,
              booking.checkin_date,
              booking.checkout_date
            )
        end)

      # Get room IDs that are booked
      booked_room_ids =
        overlapping_bookings
        |> Enum.flat_map(fn booking ->
          if Ecto.assoc_loaded?(booking.rooms) do
            Enum.map(booking.rooms, & &1.id)
          else
            []
          end
        end)
        |> MapSet.new()

      # Check if there's at least one room not booked
      available_rooms =
        Enum.filter(all_rooms, fn room -> not MapSet.member?(booked_room_ids, room.id) end)

      length(available_rooms) > 0
    end
  end
end
