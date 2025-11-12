defmodule YscWeb.ClearLakeBookingLive do
  use YscWeb, :live_view

  alias Ysc.Bookings
  alias Ysc.Bookings.Season
  alias Ysc.Bookings.SeasonHelpers
  alias Ysc.Bookings.PricingHelpers
  alias Ysc.MoneyHelper
  alias Ysc.Accounts
  alias Ysc.Subscriptions
  require Logger

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

    # Load user with subscriptions if signed in
    user_with_subs =
      if user do
        Accounts.get_user!(user.id)
        |> Ysc.Repo.preload(:subscriptions)
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
        selected_booking_mode: :day,
        guests_count: guests_count,
        max_guests: @max_guests,
        calculated_price: nil,
        price_error: nil,
        form_errors: %{},
        date_validation_errors: %{},
        date_form: date_form,
        membership_type: membership_type,
        active_tab: active_tab,
        can_book: can_book,
        booking_disabled_reason: booking_disabled_reason,
        load_radar: true
      )

    # If dates are present and user can book, initialize validation and price calculation
    socket =
      if checkin_date && checkout_date && can_book do
        socket
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
    requested_tab = parse_tab_from_params(params)

    # Check if user can book (re-check in case user state changed)
    user = socket.assigns.current_user
    {can_book, booking_disabled_reason} = check_booking_eligibility(user)

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
         tab_changed do
      today = Date.utc_today()

      {current_season, season_start_date, season_end_date} =
        SeasonHelpers.get_current_season_info(:clear_lake, today)

      max_booking_date = SeasonHelpers.calculate_max_booking_date(:clear_lake, today)

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
          page_title: "Clear Lake Cabin",
          checkin_date: checkin_date,
          checkout_date: checkout_date,
          today: today,
          max_booking_date: max_booking_date,
          current_season: current_season,
          season_start_date: season_start_date,
          season_end_date: season_end_date,
          guests_count: guests_count,
          calculated_price: nil,
          price_error: nil,
          form_errors: %{},
          date_form: date_form,
          date_validation_errors: %{},
          active_tab: active_tab,
          can_book: can_book,
          booking_disabled_reason: booking_disabled_reason
        )
        |> then(fn s ->
          # Only run price calculation if dates changed, not just tab
          if checkin_date != socket.assigns.checkin_date ||
               checkout_date != socket.assigns.checkout_date ||
               guests_count != socket.assigns.guests_count do
            s
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
  def render(assigns) do
    ~H"""
    <div class="py-8 lg:py-10">
      <div class="max-w-screen-lg mx-auto flex flex-col px-4 space-y-6">
        <div class="prose prose-zinc">
          <h1>Clear Lake Cabin</h1>
          <p>
            Select your dates and number of guests to make a reservation at our Clear Lake cabin.
          </p>
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
                <p><%= @booking_disabled_reason %></p>
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
          <!-- Date Selection -->
          <div class="space-y-4">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <.date_range_picker
                  label="Check-in & Check-out Dates"
                  id="booking_date_range"
                  form={@date_form}
                  start_date_field={@date_form[:checkin_date]}
                  end_date_field={@date_form[:checkout_date]}
                  min={@today}
                  max={@max_booking_date}
                  property={:clear_lake}
                  today={@today}
                />
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
          <!-- Submit Button -->
          <div>
            <button
              :if={
                @can_book &&
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
                <strong>💡 Tip:</strong>
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

    query_params =
      build_query_params(
        socket.assigns.checkin_date,
        socket.assigns.checkout_date,
        guests_count,
        socket.assigns.active_tab
      )

    socket =
      socket
      |> assign(guests_count: guests_count, calculated_price: nil, price_error: nil)
      |> calculate_price_if_ready()
      |> push_patch(to: ~p"/bookings/clear-lake?#{URI.encode_query(query_params)}")

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
          active_tab
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

  defp check_booking_eligibility(nil) do
    {
      false,
      "You must be signed in to make a booking. Please sign in to continue."
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

  defp update_url_with_dates(socket, checkin_date, checkout_date) do
    guests_count = socket.assigns.guests_count || 1
    active_tab = socket.assigns.active_tab || :booking

    query_params =
      build_query_params(checkin_date, checkout_date, guests_count, active_tab)

    if map_size(query_params) > 0 do
      push_patch(socket, to: ~p"/bookings/clear-lake?#{URI.encode_query(query_params)}")
    else
      push_patch(socket, to: ~p"/bookings/clear-lake")
    end
  end

  defp build_query_params(checkin_date, checkout_date, guests_count, active_tab) do
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
      if guests_count && guests_count != 1 do
        Map.put(params, "guests_count", Integer.to_string(guests_count))
      else
        params
      end

    params =
      if active_tab && active_tab != :booking do
        Map.put(params, "tab", Atom.to_string(active_tab))
      else
        params
      end

    params
  end
end
