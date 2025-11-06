defmodule YscWeb.ClearLakeBookingLive do
  use YscWeb, :live_view

  alias Ysc.Bookings
  alias Ysc.Bookings.Season
  alias Ysc.MoneyHelper
  alias Ysc.Accounts
  alias Ysc.Subscriptions
  alias Ysc.Repo
  require Logger
  import Ecto.Query

  @max_guests 12

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user

    today = Date.utc_today()
    max_booking_date = calculate_max_booking_date(today)

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

    # Load user with subscriptions if logged in
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
        page_title: "YSC Clear Lake Cabin",
        property: :clear_lake,
        user: user_with_subs,
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        today: today,
        max_booking_date: max_booking_date,
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
        booking_disabled_reason: booking_disabled_reason
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
          <h1>YSC Clear Lake Cabin</h1>
          <p>
            Select your dates and number of guests to make a reservation at our Clear Lake cabin.
          </p>
        </div>

        <.flash_group flash={@flash} />
        <!-- Booking Eligibility Banner -->
        <div :if={!@can_book} class="bg-amber-50 border border-amber-200 rounded-lg p-4">
          <div class="flex items-start">
            <div class="flex-shrink-0">
              <.icon name="hero-exclamation-triangle" class="h-5 w-5 text-amber-600" />
            </div>
            <div class="ml-3 flex-1">
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
          class="space-y-6 prose prose-zinc px-4 lg:px-0 mx-auto lg:mx-0"
        >
          <!-- About the Cabin -->
          <div>
            <h2>About the Cabin</h2>
            <p>
              The Young Scandinavians Club owns a slice of paradise on the shores of Clear Lake, California's largest natural lake. Located 2 1/2 hours north of San Francisco, the Clear Lake cabin is open as a weekend destination for YSC members from May through September, featuring the perfect climate for this camping-style lakeside location. During the winter season the cabin is available for full buyout, and will be setup with beds in the two front rooms and in the ladies' locker room.
            </p>
            <p>
              Many of the events the YSC organizes at the cabin throughout the summer include meals. If you are going up to the cabin for an event, please see the event description for information on what will be provided.
            </p>
          </div>
          <!-- Location -->
          <div>
            <h3>Location</h3>
            <p><strong>Address</strong></p>
            <p>9325 Bass Road, Kelseyville, CA 95451</p>
            <p>
              You will nearly certainly arrive by car, as the public transportation possibilities are almost non-existent.
            </p>
          </div>
          <!-- Directions -->
          <div>
            <h3>Directions from San Francisco</h3>
            <ol>
              <li>Take HWY 101 North past Santa Rosa</li>
              <li>Take the River Road/Guerneville Exit (exit 494)</li>
              <li>
                Turn Right onto Mark West Springs Rd (becomes Porter Creek Rd) and go 10.5 miles until it ends
              </li>
              <li>
                Turn Left at the stop sign onto Petrified Forrest Rd towards Calistoga and go 4.6 miles until it ends
              </li>
              <li>Turn Left at the stop sign onto Foothill Blvd/HWY 128 and go for 0.8 miles</li>
              <li>Turn Right onto Tubbs Lane and go for 1.3 miles until it ends</li>
              <li>
                Turn Left onto Hwy 29 and go for 28 miles over Mt. Saint Helena through Middletown to the stoplight in Lower Lake
              </li>
              <li>
                Turn Left onto Hwy 29 at Lower Lake (Shell Station on left) and go for 7.5 miles
              </li>
              <li>
                Turn Right onto Soda Bay Road/Hwy 281 (Kits Corner Store on right) and go for 4.3 miles
              </li>
              <li>
                Turn Right onto Bass Road (just after Montezuma Way and a church) and go for 0.3 miles
              </li>
              <li>Turn Right at the third driveway with the YSC sign</li>
            </ol>
            <p>
              <strong>Note:</strong> If you come to Konocti Harbor Inn, you've just missed Bass Road.
            </p>
          </div>
          <!-- Parking -->
          <div>
            <h3>Parking</h3>
            <p>
              Parking is limited, so please try to park as close to the next car as possible, and choose a parking spot according to when you plan to leave. Otherwise you may find yourself blocked in on Sunday morning.
            </p>
          </div>
          <!-- Accommodations -->
          <div>
            <h3>Accommodations</h3>
            <p>
              Sleep under the stars on the main lawn (mattresses are provided), or pitch a tent on the back lawn. Tent space is limited, so please do not bring a large tent to a busy weekend. To sleep outside in California's dry, mosquito-free climate is wonderful. Please note that the lawn sprinklers run at 4am on Mondays, Tuesdays and Wednesdays.
            </p>
          </div>
          <!-- Water -->
          <div>
            <h3>Water</h3>
            <p>
              <a href="#" target="_blank">Water System Operations Manual</a>
            </p>
          </div>
          <!-- What to Bring -->
          <div>
            <h3>What to Bring</h3>
            <p>
              Bring a sleeping bag, pillow, towel, swimsuit, sunscreen, flip-flops, and anything else you may need for fun activities at the lake. If you are going up for a YSC event, you may want to bring your dancing shoes, or earplugs depending on when you plan on turning in for the night. Tap water at the cabin is safe to drink, but many members bring a cooler full of ice, bottled water, and other necessities. The nearest store is 5 miles (8km) away.
            </p>
          </div>
          <!-- Boating -->
          <div>
            <h3>Boating</h3>
            <p>
              Private boats are welcome. There is no fee for boats being moored overnight but please let the cabin master know in advance so that we can make sure there is room for everyone. Please note that boat trailers cannot be parked on the YSC grounds. All boats must comply with the new Invasive Mussel Program. There is a $1,000 fine for non-compliance.
            </p>
          </div>
          <!-- Quiet Hours -->
          <div>
            <h3>Quiet Hours</h3>
            <p>
              All lights and music must be turned off at midnight. This does not apply to specially denoted party weekends. Please see the description of specific events for additional information.
            </p>
          </div>
          <!-- General Responsibilities -->
          <div>
            <h3>General Responsibilities</h3>
            <p>
              We have a list of chores, and ALL guests are expected to sign up for these upon arrival. The success of any Clear Lake event relies on EVERYONE helping out.
            </p>
          </div>
          <!-- Code of Conduct -->
          <div>
            <h3>Code of Conduct</h3>
            <p>
              Everyone who attends events hosted by the Club, including stays at the Tahoe or Clear Lake properties, should always experience a safe and positive environment. Any displays or behaviors that can be perceived as discriminating or threatening are not allowed, and the cabin master or event host have the right to determine whether something goes against our policy of making everyone feel welcome.
            </p>
            <p>
              <a href="https://ysc.org/non-discrimination-code-of-conduct/" target="_blank">
                Link to our code of conduct
              </a>
            </p>
            <p>
              <a href="https://ysc.org/conduct-violation-report-form/" target="_blank">
                Link to our conduct violation report
              </a>
            </p>
          </div>
          <!-- Children -->
          <div>
            <h3>Children</h3>
            <p>
              For general visits, Clear Lake is perfectly suitable for families with children. The cabin is paradise for kids. Some dedicated party weekends may however not be suitable for children. Please refer to the description of specific events for guidance.
            </p>
          </div>
          <!-- Pets -->
          <div>
            <h3>Pets</h3>
            <p>
              Dogs and other pets are <strong>NOT</strong>
              allowed anywhere on YSC properties. This includes the campground outside the Clear Lake cabin.
            </p>
          </div>
          <!-- Non Member Guests -->
          <div>
            <h3>Non Member Guests</h3>
            <p>
              For general visits, guests are welcome. Please note that all guests must be included and paid for in the reservation made by the member that is bringing them. Certain events may have additional capacity restrictions on non-member guests. Please refer the event description for details.
            </p>
          </div>
          <!-- Cabin -->
          <div>
            <h3>Cabin</h3>
            <p>
              The cabin has a large kitchen, men's and women's bathrooms and changing rooms, and a living room/dance floor.
            </p>
          </div>
          <!-- Things to Do Nearby -->
          <div>
            <h3>Things to Do Nearby</h3>
            <p>
              While most people find plenty to do at the Cabin, these nearby attractions may appeal to some members:
            </p>
            <ul>
              <li>
                <strong>Lake County Tourism Board</strong>
                - <a href="#" target="_blank">Click here for more info</a>
              </li>
              <li>
                <strong>Konocti Trails</strong> - <a href="#" target="_blank">Hiking Mount Konocti</a>
              </li>
              <li>
                <strong>Clear Lake State Park</strong>
              </li>
              <li>
                <strong>Wine Tasting</strong> - Visit one of more than a dozen Lake County wineries
              </li>
            </ul>
          </div>
          <!-- Booking Rules Summary -->
          <div class="bg-blue-50 border border-blue-200 rounded-md p-4 prose prose-blue">
            <h2 class="text-blue-900 mb-3">📋 Quick Booking Rules Reference</h2>
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

  defp check_booking_eligibility(nil) do
    {
      false,
      "You must be logged in to make a booking. Please log in to continue."
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

  defp parse_query_params(params, uri) when is_map(params) do
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

  # Calculate max booking date based on the most restrictive season's configuration
  # This ensures users can't select dates in restricted seasons even when currently
  # in an unrestricted season
  defp calculate_max_booking_date(today) do
    # Get all seasons for the property
    seasons = Bookings.list_seasons(:clear_lake)

    # Find the most restrictive advance_booking_days limit
    most_restrictive_limit =
      seasons
      |> Enum.filter(fn season ->
        season.advance_booking_days && season.advance_booking_days > 0
      end)
      |> Enum.map(fn season -> season.advance_booking_days end)
      |> Enum.min(fn -> nil end)

    if most_restrictive_limit do
      # Apply the most restrictive limit to prevent booking dates in restricted seasons
      Date.add(today, most_restrictive_limit)
    else
      # No restrictions - return a far future date (effectively no limit)
      # Using 10 years from now as a practical maximum
      Date.add(today, 365 * 10)
    end
  end
end
