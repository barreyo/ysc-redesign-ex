defmodule YscWeb.Components.AvailabilityCalendar do
  @moduledoc """
  LiveView component for displaying availability calendar with spot counts.

  Shows how many spots are available for each day and allows date selection.
  """
  use YscWeb, :live_component

  alias Ysc.Bookings

  @week_start_at :sunday

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="availability-calendar overflow-visible" data-phx-component={@id}>
      <div class="bg-white rounded-lg border border-zinc-200 p-6 overflow-visible">
        <div class="flex justify-between items-center mb-4">
          <div>
            <button
              type="button"
              phx-target={@myself}
              phx-click="prev-month"
              class="p-1.5 text-zinc-400 hover:text-zinc-500 transition duration-300"
            >
              <.icon name="hero-arrow-left" />
            </button>
          </div>

          <div class="font-semibold text-lg">
            <%= @current.month %>
          </div>

          <div>
            <button
              type="button"
              phx-target={@myself}
              phx-click="next-month"
              class="p-1.5 text-zinc-400 hover:text-zinc-500 transition duration-300"
            >
              <.icon name="hero-arrow-right" />
            </button>
          </div>
        </div>

        <div class="text-sm text-center mb-2">
          <.link phx-click="today" phx-target={@myself} class="text-zinc-700 hover:text-zinc-500">
            Today
          </.link>
        </div>

        <div class="text-center grid grid-cols-7 text-xs leading-6 text-zinc-800 font-semibold mb-2">
          <div :for={week_day <- List.first(@current.week_rows)}>
            <%= Calendar.strftime(week_day, "%a") %>
          </div>
        </div>

        <div
          id={"#{@id}_calendar_days"}
          class="isolate grid grid-cols-7 gap-1 text-sm overflow-visible relative"
          phx-hook="DaterangeHover"
          phx-target={@myself}
          data-component-id={@id}
        >
          <div :for={day <- Enum.flat_map(@current.week_rows, & &1)} class="relative overflow-visible">
            <div
              :if={
                date_disabled?(
                  day,
                  @min,
                  @checkin_date,
                  @state,
                  @max,
                  @property,
                  @today,
                  @selected_booking_mode,
                  @availability,
                  @seasons
                ) && !other_month?(day, @current.date) && !selected_start?(day, @checkin_date)
              }
              class="group relative overflow-visible"
            >
              <button
                type="button"
                phx-target={@myself}
                phx-click="pick-date"
                phx-value-date={Calendar.strftime(day, "%Y-%m-%d")}
                disabled={true}
                class={
                  [
                    "calendar-day overflow-hidden py-2 h-16 rounded w-full focus:z-10 transition duration-300 flex flex-col items-center justify-center",
                    today?(day) && "font-bold border-2 border-zinc-400",
                    # Red styling for dates with day bookings when in buyout mode
                    # Buyout cannot be booked if there are ANY day bookings on that day
                    if @selected_booking_mode == :buyout do
                      case Map.get(@availability, day) do
                        %{day_bookings_count: count} when count > 0 ->
                          "bg-red-200 border border-red-300 text-zinc-900 cursor-not-allowed"

                        _ ->
                          nil
                      end
                    else
                      nil
                    end,
                    # Fully red styling for dates with both checkout and checkin (not selectable at all)
                    case Map.get(@availability, day) do
                      %{has_checkout: checkout, has_checkin: checkin}
                      when checkout == true and checkin == true ->
                        if !is_blacked_out?(day, @availability) do
                          "bg-red-200 border border-red-300 text-zinc-900 cursor-not-allowed"
                        else
                          nil
                        end

                      _ ->
                        nil
                    end,
                    # Half green / half red styling for dates with check-in but no checkout
                    # Only show gradients for buyout mode (not for shared/day mode bookings)
                    if @selected_booking_mode == :buyout do
                      case Map.get(@availability, day) do
                        %{has_checkin: checkin, has_checkout: checkout}
                        when checkin == true and checkout != true ->
                          if !is_blacked_out?(day, @availability) do
                            "bg-gradient-to-r from-green-50 to-red-100 border-l-2 border-r-2 border-l-green-200 border-r-red-300 text-zinc-900"
                          else
                            nil
                          end

                        _ ->
                          nil
                      end
                    else
                      nil
                    end,
                    # Half green / half red styling for dates with checkout but no check-in
                    # Only show gradients for buyout mode (not for shared/day mode bookings)
                    if @selected_booking_mode == :buyout do
                      case Map.get(@availability, day) do
                        %{has_checkout: checkout, has_checkin: checkin}
                        when checkout == true and checkin != true ->
                          if !is_blacked_out?(day, @availability) do
                            "bg-gradient-to-r from-red-100 to-green-50 border-l-2 border-r-2 border-l-red-300 border-r-green-200 text-zinc-900"
                          else
                            nil
                          end

                        _ ->
                          nil
                      end
                    else
                      nil
                    end,
                    # Different colors based on unavailability reason (only if not a changeover day)
                    !has_checkout?(day, @availability) &&
                      !has_checkin?(day, @availability) &&
                      unavailability_type(
                        day,
                        @min,
                        @checkin_date,
                        @state,
                        @max,
                        @property,
                        @today,
                        @selected_booking_mode,
                        @availability,
                        @seasons
                      ) == :blackout &&
                      "text-red-100 cursor-not-allowed bg-red-800 border border-red-900",
                    !has_checkout?(day, @availability) &&
                      !has_checkin?(day, @availability) &&
                      unavailability_type(
                        day,
                        @min,
                        @checkin_date,
                        @state,
                        @max,
                        @property,
                        @today,
                        @selected_booking_mode,
                        @availability,
                        @seasons
                      ) == :bookings &&
                      "text-red-200 cursor-not-allowed bg-red-200 border border-red-300",
                    !has_checkout?(day, @availability) &&
                      !has_checkin?(day, @availability) &&
                      unavailability_type(
                        day,
                        @min,
                        @checkin_date,
                        @state,
                        @max,
                        @property,
                        @today,
                        @selected_booking_mode,
                        @availability,
                        @seasons
                      ) == :other &&
                      "text-zinc-300 cursor-not-allowed opacity-50 bg-zinc-100"
                  ]
                }
              >
                <time class="text-sm font-medium" datetime={Calendar.strftime(day, "%Y-%m-%d")}>
                  <%= Calendar.strftime(day, "%d") %>
                </time>
              </button>
              <span
                role="tooltip"
                class={[
                  "absolute transition-opacity mt-2 top-full left-1/2 transform -translate-x-1/2 duration-200 opacity-0 z-[100] text-xs font-medium text-zinc-100 bg-zinc-900 rounded-lg shadow-lg px-4 py-2 block rounded tooltip group-hover:opacity-100 whitespace-normal pointer-events-none",
                  "min-w-[200px] max-w-[400px]",
                  "text-left"
                ]}
              >
                <%= unavailability_reason(
                  day,
                  @min,
                  @checkin_date,
                  @state,
                  @max,
                  @property,
                  @today,
                  @selected_booking_mode,
                  @availability,
                  @seasons
                ) %>
              </span>
            </div>
            <button
              :if={
                !date_disabled?(
                  day,
                  @min,
                  @checkin_date,
                  @state,
                  @max,
                  @property,
                  @today,
                  @selected_booking_mode,
                  @availability,
                  @seasons
                ) || other_month?(day, @current.date) || selected_start?(day, @checkin_date)
              }
              type="button"
              phx-target={@myself}
              phx-click="pick-date"
              phx-value-date={Calendar.strftime(day, "%Y-%m-%d")}
              disabled={
                date_disabled?(
                  day,
                  @min,
                  @checkin_date,
                  @state,
                  @max,
                  @property,
                  @today,
                  @selected_booking_mode,
                  @availability,
                  @seasons
                ) && !selected_start?(day, @checkin_date)
              }
              class={
                [
                  "calendar-day overflow-hidden py-2 h-16 rounded w-full focus:z-10 transition duration-300 flex flex-col items-center justify-center",
                  # Highlight start date with nicer styling (highest priority - must come first)
                  selected_start?(day, @checkin_date) &&
                    "bg-gradient-to-br from-blue-600 to-blue-700 text-white font-bold shadow-lg ring-4 ring-blue-200 ring-offset-2 transform scale-105 relative z-30",
                  # Highlight end date (actual or hovered) with nicer styling
                  (selected_end?(day, @checkout_date) ||
                     (@state == :set_end && @hover_checkout_date && day == @hover_checkout_date)) &&
                    !selected_start?(day, @checkin_date) &&
                    "bg-gradient-to-br from-blue-600 to-blue-700 text-white font-bold shadow-lg ring-4 ring-blue-200 ring-offset-2 transform scale-105 relative z-30",
                  # Highlight dates in the selected or hovered range (but not start/end dates)
                  (selected_range?(day, @checkin_date, @hover_checkout_date || @checkout_date) ||
                     (in_hover_range?(day, @checkin_date, @hover_checkout_date) && @state == :set_end)) &&
                    !selected_start?(day, @checkin_date) &&
                    !selected_end?(day, @checkout_date) &&
                    !(@state == :set_end && @hover_checkout_date && day == @hover_checkout_date) &&
                    "bg-blue-400 text-white hover:bg-blue-500",
                  # Red styling for dates with day bookings when in buyout mode
                  # Buyout cannot be booked if there are ANY day bookings on that day
                  if @selected_booking_mode == :buyout &&
                       !other_month?(day, @current.date) &&
                       !selected_start?(day, @checkin_date) &&
                       !selected_end?(day, @checkout_date) &&
                       !(@state == :set_end && @hover_checkout_date && day == @hover_checkout_date) &&
                       !selected_range?(day, @checkin_date, @hover_checkout_date || @checkout_date) &&
                       !(in_hover_range?(day, @checkin_date, @hover_checkout_date) &&
                           @state == :set_end) do
                    case Map.get(@availability, day) do
                      %{day_bookings_count: count} when count > 0 ->
                        "bg-red-200 border border-red-300 text-zinc-900 cursor-not-allowed"

                      _ ->
                        nil
                    end
                  else
                    nil
                  end,
                  # Fully red styling for dates with both checkout and checkin (not selectable at all)
                  # Must come before other styling to take precedence
                  if !other_month?(day, @current.date) &&
                       !selected_start?(day, @checkin_date) &&
                       !selected_end?(day, @checkout_date) &&
                       !(@state == :set_end && @hover_checkout_date && day == @hover_checkout_date) &&
                       !selected_range?(day, @checkin_date, @hover_checkout_date || @checkout_date) &&
                       !(in_hover_range?(day, @checkin_date, @hover_checkout_date) &&
                           @state == :set_end) do
                    case Map.get(@availability, day) do
                      %{has_checkout: checkout, has_checkin: checkin} = info
                      when checkout == true and checkin == true ->
                        if !is_blacked_out?(day, @availability) do
                          "bg-red-200 border border-red-300 text-zinc-900 cursor-not-allowed"
                        else
                          nil
                        end

                      _ ->
                        nil
                    end
                  else
                    nil
                  end,
                  # Half green / half red styling for dates with check-in but no checkout
                  # Only show gradients for buyout mode (not for shared/day mode bookings)
                  # These can be used as checkout dates for same-day turnarounds
                  if @selected_booking_mode == :buyout &&
                       !other_month?(day, @current.date) &&
                       !selected_start?(day, @checkin_date) &&
                       !selected_end?(day, @checkout_date) &&
                       !(@state == :set_end && @hover_checkout_date && day == @hover_checkout_date) &&
                       !selected_range?(day, @checkin_date, @hover_checkout_date || @checkout_date) &&
                       !(in_hover_range?(day, @checkin_date, @hover_checkout_date) &&
                           @state == :set_end) do
                    case Map.get(@availability, day) do
                      %{has_checkin: checkin, has_checkout: checkout}
                      when checkin == true and checkout != true ->
                        if !is_blacked_out?(day, @availability) do
                          "bg-gradient-to-r from-green-50 to-red-100 border-l-2 border-r-2 border-l-green-200 border-r-red-300 text-zinc-900"
                        else
                          nil
                        end

                      _ ->
                        nil
                    end
                  else
                    nil
                  end,
                  # Half green / half red styling for dates with checkout but no check-in
                  # Only show gradients for buyout mode (not for shared/day mode bookings)
                  # These can be used as check-in dates for same-day turnarounds
                  # Left side red (checkout happening), right side green (available for check-in)
                  if @selected_booking_mode == :buyout &&
                       !other_month?(day, @current.date) &&
                       !selected_start?(day, @checkin_date) &&
                       !selected_end?(day, @checkout_date) &&
                       !(@state == :set_end && @hover_checkout_date && day == @hover_checkout_date) &&
                       !selected_range?(day, @checkin_date, @hover_checkout_date || @checkout_date) &&
                       !(in_hover_range?(day, @checkin_date, @hover_checkout_date) &&
                           @state == :set_end) do
                    case Map.get(@availability, day) do
                      %{has_checkout: checkout, has_checkin: checkin}
                      when checkout == true and checkin != true ->
                        if !is_blacked_out?(day, @availability) do
                          "bg-gradient-to-r from-red-100 to-green-50 border-l-2 border-r-2 border-l-red-300 border-r-green-200 text-zinc-900"
                        else
                          nil
                        end

                      _ ->
                        nil
                    end
                  else
                    nil
                  end,
                  # Light green background for available dates (not disabled, not selected, not in range, not other month, and has availability data)
                  !date_disabled?(
                    day,
                    @min,
                    @checkin_date,
                    @state,
                    @max,
                    @property,
                    @today,
                    @selected_booking_mode,
                    @availability,
                    @seasons
                  ) &&
                    !other_month?(day, @current.date) &&
                    !selected_start?(day, @checkin_date) &&
                    !selected_end?(day, @checkout_date) &&
                    !(@state == :set_end && @hover_checkout_date && day == @hover_checkout_date) &&
                    !selected_range?(day, @checkin_date, @hover_checkout_date || @checkout_date) &&
                    !(in_hover_range?(day, @checkin_date, @hover_checkout_date) && @state == :set_end) &&
                    Map.has_key?(@availability, day) &&
                    !is_changeover_day?(day, @availability) &&
                    "bg-green-50 border border-green-200 text-zinc-900",
                  today?(day) && "font-bold border-2 border-zinc-400",
                  # Show hover effect only when not in range selection mode and not disabled
                  !date_disabled?(
                    day,
                    @min,
                    @checkin_date,
                    @state,
                    @max,
                    @property,
                    @today,
                    @selected_booking_mode,
                    @availability,
                    @seasons
                  ) &&
                    !before_min_date?(day, @min) &&
                    @state != :set_end &&
                    is_changeover_day?(day, @availability) &&
                    "hover:from-green-100 hover:to-red-200",
                  !date_disabled?(
                    day,
                    @min,
                    @checkin_date,
                    @state,
                    @max,
                    @property,
                    @today,
                    @selected_booking_mode,
                    @availability,
                    @seasons
                  ) &&
                    !before_min_date?(day, @min) &&
                    @state != :set_end &&
                    !is_changeover_day?(day, @availability) &&
                    "hover:bg-green-100 hover:border-green-300",
                  # Different colors for disabled dates based on reason (but not if it's the selected start date)
                  # Exclude dates with check-in/checkout from disabled styling (they have special styling)
                  date_disabled?(
                    day,
                    @min,
                    @checkin_date,
                    @state,
                    @max,
                    @property,
                    @today,
                    @selected_booking_mode,
                    @availability,
                    @seasons
                  ) &&
                    !selected_start?(day, @checkin_date) &&
                    !has_checkout?(day, @availability) &&
                    !has_checkin?(day, @availability) &&
                    unavailability_type(
                      day,
                      @min,
                      @checkin_date,
                      @state,
                      @max,
                      @property,
                      @today,
                      @selected_booking_mode,
                      @availability,
                      @seasons
                    ) == :blackout &&
                    "text-red-100 cursor-not-allowed bg-red-800 border border-red-900",
                  date_disabled?(
                    day,
                    @min,
                    @checkin_date,
                    @state,
                    @max,
                    @property,
                    @today,
                    @selected_booking_mode,
                    @availability,
                    @seasons
                  ) &&
                    !selected_start?(day, @checkin_date) &&
                    !has_checkout?(day, @availability) &&
                    !has_checkin?(day, @availability) &&
                    unavailability_type(
                      day,
                      @min,
                      @checkin_date,
                      @state,
                      @max,
                      @property,
                      @today,
                      @selected_booking_mode,
                      @availability,
                      @seasons
                    ) == :bookings &&
                    "text-red-200 cursor-not-allowed bg-red-200 border border-red-300",
                  date_disabled?(
                    day,
                    @min,
                    @checkin_date,
                    @state,
                    @max,
                    @property,
                    @today,
                    @selected_booking_mode,
                    @availability,
                    @seasons
                  ) &&
                    !selected_start?(day, @checkin_date) &&
                    !has_checkout?(day, @availability) &&
                    !has_checkin?(day, @availability) &&
                    unavailability_type(
                      day,
                      @min,
                      @checkin_date,
                      @state,
                      @max,
                      @property,
                      @today,
                      @selected_booking_mode,
                      @availability,
                      @seasons
                    ) == :other &&
                    "text-zinc-300 cursor-not-allowed opacity-50 bg-zinc-100",
                  other_month?(day, @current.date) && "text-zinc-400"
                ]
              }
            >
              <time class="text-sm font-medium" datetime={Calendar.strftime(day, "%Y-%m-%d")}>
                <%= Calendar.strftime(day, "%d") %>
              </time>
              <div
                :if={
                  (!date_disabled?(
                     day,
                     @min,
                     @checkin_date,
                     @state,
                     @max,
                     @property,
                     @today,
                     @selected_booking_mode,
                     @availability,
                     @seasons
                   ) || selected_start?(day, @checkin_date)) && !other_month?(day, @current.date)
                }
                class="text-xs mt-1"
              >
                <%= availability_display(day, @selected_booking_mode, @availability) %>
              </div>
            </button>
          </div>
        </div>

        <div class="mt-8 flex flex-wrap gap-4 text-xs text-zinc-600">
          <div class="flex items-center gap-2">
            <div class="w-4 h-4 bg-green-50 border border-green-200 rounded"></div>
            <span>Available</span>
          </div>
          <div class="flex items-center gap-2">
            <div class="w-4 h-4 bg-blue-500 rounded"></div>
            <span>Selected dates</span>
          </div>
          <div class="flex items-center gap-2">
            <div class="w-4 h-4 bg-red-800 border border-red-900 rounded"></div>
            <span>Blackout dates</span>
          </div>
          <div class="flex items-center gap-2">
            <div class="w-4 h-4 bg-red-200 border border-red-300 rounded"></div>
            <span>Unavailable (bookings)</span>
          </div>
          <div class="flex items-center gap-2">
            <div class="w-4 h-4 bg-zinc-100 border border-zinc-300 rounded"></div>
            <span>Other restrictions</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    today = Date.utc_today()

    {
      :ok,
      socket
      |> assign(:current, format_date(today))
      |> assign(:checkin_date, nil)
      |> assign(:checkout_date, nil)
      |> assign(:hover_checkout_date, nil)
      |> assign(:state, :set_start)
      |> assign(:availability, %{})
      |> assign(:seasons, [])
    }
  end

  @impl true
  def update(assigns, socket) do
    # Calculate date range for availability (show 3 months)
    today = assigns[:today] || Date.utc_today()

    # Preserve current date if we have one, otherwise use today
    current_date =
      if socket.assigns[:current] && socket.assigns.current[:date] do
        socket.assigns.current.date
      else
        today
      end

    # Calculate availability range to include the visible calendar month
    # We need to ensure the range covers at least the current month being viewed
    # Calculate start and end dates to cover the visible month plus buffer
    visible_month_start = Date.beginning_of_month(current_date)
    visible_month_end = Date.end_of_month(current_date)

    # Expand range to cover visible month plus 30 days before and after for context
    month_start_minus_30 = Date.add(visible_month_start, -30)

    start_date =
      if Date.compare(month_start_minus_30, today) == :lt, do: today, else: month_start_minus_30

    end_date = Date.add(visible_month_end, 30)

    # Also ensure we cover any selected dates
    checkin_date = assigns[:checkin_date]
    checkout_date = assigns[:checkout_date]

    {start_date, end_date} =
      cond do
        checkin_date && checkout_date ->
          # Expand range to include selected dates
          {
            if(Date.compare(start_date, checkin_date) == :gt, do: checkin_date, else: start_date)
            |> Date.add(-30),
            if(Date.compare(end_date, checkout_date) == :lt, do: checkout_date, else: end_date)
            |> Date.add(30)
          }

        checkin_date ->
          # Expand range to include check-in date
          {
            if(Date.compare(start_date, checkin_date) == :gt, do: checkin_date, else: start_date)
            |> Date.add(-30),
            if(Date.compare(end_date, checkin_date) == :lt, do: checkin_date, else: end_date)
            |> Date.add(30)
          }

        true ->
          {start_date, end_date}
      end

    # Check if we need to reload availability data
    # Only reload if the date range has changed or if we don't have availability data yet
    # Compare dates using Date.compare to handle struct comparison correctly
    # Also check if the availability data covers the needed date range
    existing_today = socket.assigns[:today]
    _today_changed = is_nil(existing_today) || Date.compare(existing_today, today) != :eq

    # Check if existing availability data covers the needed range
    existing_availability = socket.assigns[:availability]

    has_valid_availability =
      if !is_nil(existing_availability) && !is_nil(existing_today) &&
           Date.compare(existing_today, today) == :eq do
        # Check if the existing availability covers the needed range
        # Get the min and max dates from the availability map
        availability_dates = Map.keys(existing_availability)

        if Enum.empty?(availability_dates) do
          false
        else
          existing_min = Enum.min(availability_dates)
          existing_max = Enum.max(availability_dates)

          # Check if existing range covers the needed range
          Date.compare(existing_min, start_date) != :gt &&
            Date.compare(existing_max, end_date) != :lt
        end
      else
        false
      end

    # Compare booking mode, handling nil values (nil means :day by default)
    existing_booking_mode = socket.assigns[:selected_booking_mode] || :day
    new_booking_mode = assigns[:selected_booking_mode] || :day
    booking_mode_changed = existing_booking_mode != new_booking_mode

    needs_availability_reload =
      !has_valid_availability ||
        booking_mode_changed

    # Get availability data only if needed
    availability =
      if needs_availability_reload do
        Bookings.get_clear_lake_daily_availability(start_date, end_date)
      else
        socket.assigns[:availability]
      end

    # Pre-load seasons for the property to avoid repeated queries
    property = assigns[:property] || :clear_lake

    seasons =
      if socket.assigns[:seasons] && socket.assigns[:property] == property do
        # Reuse cached seasons if property hasn't changed
        socket.assigns[:seasons]
      else
        # Load seasons once
        Bookings.list_seasons(property)
      end

    checkin_date = assigns[:checkin_date]
    checkout_date = assigns[:checkout_date]

    # Determine state: if we have checkin but no checkout, we're selecting end date
    new_state =
      cond do
        checkin_date && checkout_date ->
          # Both dates selected - ready for new selection
          :set_start

        checkin_date && !checkout_date ->
          # Only checkin selected - waiting for checkout
          :set_end

        true ->
          # No dates selected - ready for checkin
          :set_start
      end

    # Assign all parent assigns first, then override with component-specific assigns
    updated_socket =
      socket
      |> assign(assigns)
      |> assign(:current, format_date(current_date))
      |> assign(:availability, availability)
      |> assign(:today, today)
      |> assign(:min, assigns[:min] || today)
      |> assign(:max, assigns[:max])
      |> assign(:property, property)
      |> assign(:seasons, seasons)
      |> assign(:selected_booking_mode, assigns[:selected_booking_mode] || :day)
      |> assign(:state, new_state)

    {:ok, updated_socket}
  end

  @impl true
  def handle_event("prev-month", _, socket) do
    new_date = prev_month_date(socket.assigns.current.date)
    socket = socket |> assign(:current, format_date(new_date))

    # Check if we need to reload availability for the new month
    socket = reload_availability_if_needed(socket, new_date)

    {:noreply, socket}
  end

  @impl true
  def handle_event("next-month", _, socket) do
    new_date = next_month_date(socket.assigns.current.date)
    socket = socket |> assign(:current, format_date(new_date))

    # Check if we need to reload availability for the new month
    socket = reload_availability_if_needed(socket, new_date)

    {:noreply, socket}
  end

  @impl true
  def handle_event("today", _, socket) do
    today = Date.utc_today()
    {:noreply, socket |> assign(:current, format_date(today))}
  end

  @impl true
  def handle_event("pick-date", %{"date" => date_str}, socket) do
    date = Date.from_iso8601!(date_str)

    # Check if date is disabled
    if date_disabled?(
         date,
         socket.assigns.min,
         socket.assigns.checkin_date,
         socket.assigns.state,
         socket.assigns[:max],
         socket.assigns[:property],
         socket.assigns[:today],
         socket.assigns[:selected_booking_mode],
         socket.assigns[:availability],
         socket.assigns[:seasons]
       ) do
      {:noreply, socket}
    else
      case socket.assigns.state do
        :set_start ->
          {
            :noreply,
            socket
            |> assign(:checkin_date, date)
            |> assign(:checkout_date, nil)
            |> assign(:state, :set_end)
            |> send_date_update()
          }

        :set_end ->
          checkin_date = socket.assigns.checkin_date

          # If clicking on the same check-in date again, reset the selection
          if Date.compare(date, checkin_date) == :eq do
            {
              :noreply,
              socket
              |> assign(:checkin_date, nil)
              |> assign(:checkout_date, nil)
              |> assign(:hover_checkout_date, nil)
              |> assign(:state, :set_start)
              |> send_date_update()
            }
          else
            if Date.compare(date, checkin_date) == :lt do
              # If selected date is before check-in, make it the new check-in
              {
                :noreply,
                socket
                |> assign(:checkin_date, date)
                |> assign(:checkout_date, nil)
                |> assign(:state, :set_end)
                |> send_date_update()
              }
            else
              # Validate the range
              if valid_date_range?(checkin_date, date, socket.assigns) do
                {
                  :noreply,
                  socket
                  |> assign(:checkout_date, date)
                  |> assign(:state, :set_start)
                  |> send_date_update()
                }
              else
                {:noreply, socket}
              end
            end
          end
      end
    end
  end

  @impl true
  def handle_event("cursor-move", date_str, socket) do
    # Handle both string and map formats
    date_string =
      if is_map(date_str),
        do: Map.get(date_str, "date") || Map.get(date_str, :date) || "",
        else: date_str

    date =
      case Date.from_iso8601(date_string) do
        {:ok, d} ->
          d

        _ ->
          # Try parsing as just a date string if ISO8601 fails
          case date_string do
            "" -> nil
            _ -> Date.from_iso8601!(date_string)
          end
      end

    if is_nil(date) do
      {:noreply, socket}
    else
      # Show hover range when we have a start date and are selecting end date
      if socket.assigns.state == :set_end && socket.assigns.checkin_date do
        checkin_date = socket.assigns.checkin_date

        hover_checkout_date =
          if Date.compare(date, checkin_date) != :lt &&
               !date_disabled?(
                 date,
                 socket.assigns.min,
                 checkin_date,
                 socket.assigns.state,
                 socket.assigns[:max],
                 socket.assigns[:property],
                 socket.assigns[:today],
                 socket.assigns[:selected_booking_mode],
                 socket.assigns[:availability],
                 socket.assigns[:seasons]
               ) &&
               valid_date_range?(checkin_date, date, socket.assigns) do
            date
          else
            nil
          end

        {:noreply, socket |> assign(:hover_checkout_date, hover_checkout_date)}
      else
        # Clear hover when not in set_end state
        {:noreply, socket |> assign(:hover_checkout_date, nil)}
      end
    end
  end

  @impl true
  def handle_event("cursor-leave", _params, socket) do
    # Clear hover when mouse leaves the calendar
    {:noreply, socket |> assign(:hover_checkout_date, nil)}
  end

  defp send_date_update(socket) do
    attrs = %{
      id: socket.assigns.id,
      checkin_date: socket.assigns.checkin_date,
      checkout_date: socket.assigns.checkout_date
    }

    send(self(), {:availability_calendar_date_changed, attrs})
    socket
  end

  # Reloads availability if the given date is outside the current availability range
  defp reload_availability_if_needed(socket, date) do
    today = socket.assigns[:today] || Date.utc_today()
    existing_availability = socket.assigns[:availability]

    # Calculate if the new month is within the existing availability range
    needs_reload =
      if !is_nil(existing_availability) && map_size(existing_availability) > 0 do
        availability_dates = Map.keys(existing_availability)
        existing_min = Enum.min_by(availability_dates, &Date.to_erl/1)
        existing_max = Enum.max_by(availability_dates, &Date.to_erl/1)

        # Check if the new month is outside the range
        month_start = Date.beginning_of_month(date)
        month_end = Date.end_of_month(date)

        Date.compare(month_start, existing_min) == :lt ||
          Date.compare(month_end, existing_max) == :gt
      else
        true
      end

    if needs_reload do
      # Calculate new availability range
      visible_month_start = Date.beginning_of_month(date)
      visible_month_end = Date.end_of_month(date)

      month_start_minus_30 = Date.add(visible_month_start, -30)

      start_date =
        if Date.compare(month_start_minus_30, today) == :lt, do: today, else: month_start_minus_30

      end_date = Date.add(visible_month_end, 30)

      # Also include selected dates if any
      {start_date, end_date} =
        if socket.assigns[:checkin_date] do
          checkin = socket.assigns[:checkin_date]
          checkout = socket.assigns[:checkout_date]

          if checkout do
            {
              if(Date.compare(start_date, checkin) == :gt, do: checkin, else: start_date)
              |> Date.add(-30),
              if(Date.compare(end_date, checkout) == :lt, do: checkout, else: end_date)
              |> Date.add(30)
            }
          else
            {
              if(Date.compare(start_date, checkin) == :gt, do: checkin, else: start_date)
              |> Date.add(-30),
              if(Date.compare(end_date, checkin) == :lt, do: checkin, else: end_date)
              |> Date.add(30)
            }
          end
        else
          {start_date, end_date}
        end

      new_availability = Bookings.get_clear_lake_daily_availability(start_date, end_date)

      socket |> assign(:availability, new_availability)
    else
      socket
    end
  end

  defp prev_month_date(date) do
    date
    |> Date.beginning_of_month()
    |> Date.add(-1)
  end

  defp next_month_date(date) do
    date
    |> Date.end_of_month()
    |> Date.add(1)
  end

  defp before_min_date?(day, min) do
    Date.compare(day, min) == :lt
  end

  defp date_disabled?(
         day,
         min,
         checkin_date,
         state,
         max,
         property,
         today,
         selected_booking_mode,
         availability,
         seasons
       ) do
    # Always disable dates before minimum
    if Date.compare(day, min) == :lt do
      IO.puts("[DEBUG] date_disabled? #{Date.to_string(day)}: true (before min)")
      true
    else
      # Check if date is after maximum (if max is set)
      if max && Date.compare(day, max) == :gt do
        IO.puts("[DEBUG] date_disabled? #{Date.to_string(day)}: true (after max)")
        true
      else
        # Check season restrictions if property is provided
        if property && today do
          unless is_date_selectable_cached?(property, day, today, seasons) do
            IO.puts("[DEBUG] date_disabled? #{Date.to_string(day)}: true (season restriction)")
            true
          else
            # Check availability
            day_availability = Map.get(availability, day)

            if day_availability do
              disabled_reason =
                cond do
                  # Rule: Cannot book if blacked out (applies to both buyout and day mode)
                  day_availability.is_blacked_out ->
                    "blacked_out"

                  # Rule: For buyout mode - cannot book if there are ANY day bookings on that day
                  # Checkout is at 11:00 AM, check-in is at 15:00 (3 PM), so same-day turnarounds are allowed
                  selected_booking_mode == :buyout ->
                    # Check if there are day bookings (shared/per person) on this date
                    if day_availability.day_bookings_count > 0 do
                      "cannot_book_buyout (has_day_bookings: #{day_availability.day_bookings_count})"
                    else
                      # Check if there's a buyout staying (not checking out/in today)
                      # Allow same-day turnarounds: checkout at 12:00, check-in at 15:00
                      is_checkout_date = state == :set_end
                      is_checkin_date = state == :set_start || is_nil(checkin_date)

                      if day_availability.has_buyout do
                        # Check if same-day turnaround is possible
                        can_same_day_turnaround =
                          (is_checkout_date && day_availability.has_checkin) ||
                            (is_checkin_date && day_availability.has_checkout)

                        if can_same_day_turnaround do
                          # Same-day turnaround allowed - check other rules
                          other_rules_result =
                            check_other_rules(
                              day,
                              checkin_date,
                              state,
                              property,
                              availability,
                              selected_booking_mode,
                              seasons
                            )

                          if other_rules_result do
                            "other_rules"
                          else
                            nil
                          end
                        else
                          "cannot_book_buyout (has_buyout_staying: true)"
                        end
                      else
                        # No buyout, no day bookings - check other rules
                        other_rules_result =
                          check_other_rules(
                            day,
                            checkin_date,
                            state,
                            property,
                            availability,
                            selected_booking_mode,
                            seasons
                          )

                        if other_rules_result do
                          "other_rules"
                        else
                          nil
                        end
                      end
                    end

                  # Rule: For day/shared mode - cannot book if there's a buyout or blackout
                  # 12 person max is already handled in can_book_day
                  selected_booking_mode == :day ->
                    if day_availability.has_buyout do
                      "cannot_book_day (has_buyout: true)"
                    else
                      # Check if there are spots available (12 person max)
                      # Checkout is at 11:00 AM, check-in is at 15:00 (3 PM), so same-day turnarounds are allowed
                      if day_availability.spots_available <= 0 do
                        "cannot_book_day (no_spots_available: #{day_availability.spots_available})"
                      else
                        # Check other rules
                        other_rules_result =
                          check_other_rules(
                            day,
                            checkin_date,
                            state,
                            property,
                            availability,
                            selected_booking_mode,
                            seasons
                          )

                        if other_rules_result do
                          "other_rules"
                        else
                          nil
                        end
                      end
                    end

                  true ->
                    # Check other rules (Saturday, range validation, etc.)
                    other_rules_result =
                      check_other_rules(
                        day,
                        checkin_date,
                        state,
                        property,
                        availability,
                        selected_booking_mode,
                        seasons
                      )

                    if other_rules_result do
                      "other_rules"
                    else
                      nil
                    end
                end

              if disabled_reason do
                IO.puts("""
                [DEBUG] date_disabled? #{Date.to_string(day)}: true (#{disabled_reason})
                  - selected_booking_mode: #{selected_booking_mode}
                  - has_checkout: #{day_availability.has_checkout}
                  - has_checkin: #{day_availability.has_checkin}
                  - is_changeover_day: #{day_availability.is_changeover_day}
                """)

                true
              else
                IO.puts("[DEBUG] date_disabled? #{Date.to_string(day)}: false (available)")
                false
              end
            else
              # Date not in availability map (outside loaded range) - disable it
              # This prevents selecting dates that haven't been loaded yet
              IO.puts(
                "[DEBUG] date_disabled? #{Date.to_string(day)}: true (not in availability map)"
              )

              true
            end
          end
        else
          result =
            check_other_rules(
              day,
              checkin_date,
              state,
              property,
              availability,
              selected_booking_mode,
              nil
            )

          IO.puts(
            "[DEBUG] date_disabled? #{Date.to_string(day)}: #{result} (no property/today check)"
          )

          result
        end
      end
    end
  end

  # Cached version of is_date_selectable? that uses pre-loaded seasons
  defp is_date_selectable_cached?(property, date, today, seasons) do
    season =
      if seasons do
        # Use pre-loaded seasons
        Ysc.Bookings.Season.find_season_for_date(seasons, date)
      else
        # Fallback to querying (shouldn't happen if seasons are loaded)
        Ysc.Bookings.Season.for_date(property, date)
      end

    if season && season.advance_booking_days && season.advance_booking_days > 0 do
      # Season has a limit - check if date is within the advance booking window
      max_booking_date = Date.add(today, season.advance_booking_days)
      Date.compare(date, max_booking_date) != :gt
    else
      # No limit for this season - date is selectable
      true
    end
  end

  defp check_other_rules(
         day,
         checkin_date,
         state,
         property,
         availability,
         selected_booking_mode,
         seasons
       ) do
    # Cannot check in on Saturday (day 6) - this applies to Tahoe only
    # Clear Lake allows Saturday check-ins
    if Date.day_of_week(day) == 6 && property == :tahoe do
      true
    else
      # When selecting end date (state is :set_end), validate against start date
      case state do
        :set_end when not is_nil(checkin_date) ->
          nights = Date.diff(day, checkin_date)

          # Get max nights from season for check-in date
          max_nights =
            if seasons && checkin_date do
              season = Ysc.Bookings.Season.find_season_for_date(seasons, checkin_date)
              Ysc.Bookings.Season.get_max_nights(season, property || :clear_lake)
            else
              # Fallback to property defaults
              case property do
                :tahoe -> 4
                :clear_lake -> 30
                _ -> 4
              end
            end

          # Disable if:
          # 1. More than max_nights
          # 2. Less than 1 night (end date before or same as start)
          # 3. Ends on Saturday (Tahoe only - Clear Lake allows Saturday checkouts)
          # 4. If range includes Saturday, must also include Sunday (Tahoe only)
          # 5. If any date in the range is blacked out or unavailable
          cond do
            nights > max_nights ->
              true

            nights < 1 ->
              true

            Date.day_of_week(day) == 6 && property == :tahoe ->
              true

            true ->
              # Check if all dates in the range are available
              # Note: Exclude the checkout date (day) from validation since checkout is at 11 AM
              # and check-in is at 3 PM, allowing same-day turnarounds
              date_range =
                if Date.compare(day, checkin_date) == :gt do
                  # Exclude checkout date - only validate nights that will be stayed
                  Date.range(checkin_date, Date.add(day, -1)) |> Enum.to_list()
                else
                  # Edge case: same day check-in/check-out (shouldn't happen, but handle gracefully)
                  []
                end

              # Check if any date in the range is blacked out or unavailable
              range_has_unavailable_date =
                if availability do
                  Enum.any?(date_range, fn range_day ->
                    day_availability = Map.get(availability, range_day)

                    if day_availability do
                      # Check if this day is blacked out or unavailable for the selected booking mode
                      day_availability.is_blacked_out ||
                        (selected_booking_mode == :day && not day_availability.can_book_day) ||
                        (selected_booking_mode == :buyout && not day_availability.can_book_buyout)
                    else
                      # Date not in availability map - consider it unavailable
                      true
                    end
                  end)
                else
                  false
                end

              if range_has_unavailable_date do
                true
              else
                # Weekend rule (Saturday must include Sunday) only applies to Tahoe
                if property == :tahoe do
                  # Check if range includes Saturday - if so, must also include Sunday
                  day_of_weeks = Enum.map(date_range, &Date.day_of_week/1)
                  has_saturday = 6 in day_of_weeks
                  has_sunday = 7 in day_of_weeks

                  if has_saturday && not has_sunday do
                    # Range includes Saturday but not Sunday - invalid (Tahoe only)
                    true
                  else
                    false
                  end
                else
                  # Clear Lake doesn't have the weekend rule
                  false
                end
              end
          end

        _ ->
          false
      end
    end
  end

  # Determines the type of unavailability for styling purposes
  # Returns :blackout, :bookings, or :other
  defp unavailability_type(
         day,
         min,
         checkin_date,
         state,
         max,
         property,
         today,
         selected_booking_mode,
         availability,
         seasons
       ) do
    # Check if date is before minimum or after maximum (these are "other" reasons)
    if Date.compare(day, min) == :lt or (max && Date.compare(day, max) == :gt) do
      :other
    else
      # Check season restrictions
      if property && today do
        unless is_date_selectable_cached?(property, day, today, seasons) do
          :other
        else
          # Check availability
          day_availability = Map.get(availability, day)

          if day_availability do
            cond do
              day_availability.is_blacked_out ->
                :blackout

              selected_booking_mode == :day && not day_availability.can_book_day ->
                # Unavailable due to bookings (not blacked out, but can't book day)
                :bookings

              selected_booking_mode == :buyout && not day_availability.can_book_buyout ->
                # Unavailable due to bookings (not blacked out, but can't book buyout)
                :bookings

              true ->
                # Other rules (Saturday, range validation, etc.)
                :other
            end
          else
            # Date not in availability map (outside loaded range) - mark as other/unavailable
            :other
          end
        end
      else
        # No property/today - check other rules
        if check_other_rules(
             day,
             checkin_date,
             state,
             property,
             availability,
             selected_booking_mode,
             nil
           ) do
          :other
        else
          :other
        end
      end
    end
  end

  defp valid_date_range?(checkin_date, checkout_date, assigns) do
    nights = Date.diff(checkout_date, checkin_date)
    property = assigns[:property]
    date_range = Date.range(checkin_date, checkout_date) |> Enum.to_list()

    # Get max nights from season for check-in date
    max_nights =
      if assigns[:seasons] && checkin_date do
        season = Ysc.Bookings.Season.find_season_for_date(assigns[:seasons], checkin_date)
        Ysc.Bookings.Season.get_max_nights(season, property || :clear_lake)
      else
        # Fallback to property defaults
        case property do
          :tahoe -> 4
          :clear_lake -> 30
          _ -> 4
        end
      end

    if nights < 1 or nights > max_nights do
      false
    else
      # Cannot end on Saturday (Tahoe only - Clear Lake allows Saturday checkouts)
      if Date.day_of_week(checkout_date) == 6 && property == :tahoe do
        false
      else
        # Weekend rule (Saturday must include Sunday) only applies to Tahoe
        weekend_rule_passes =
          if property == :tahoe do
            # If range includes Saturday, must also include Sunday
            day_of_weeks = Enum.map(date_range, &Date.day_of_week/1)
            has_saturday = 6 in day_of_weeks
            has_sunday = 7 in day_of_weeks

            if has_saturday && not has_sunday do
              false
            else
              true
            end
          else
            # Clear Lake doesn't have the weekend rule
            true
          end

        if not weekend_rule_passes do
          false
        else
          # Check that ALL dates in the range are available
          # This ensures no unavailable dates in the middle of the range
          # For dates in the middle, we only check availability (not end-date rules)
          # For the end date, we check both availability and end-date rules
          all_dates_available =
            Enum.all?(date_range, fn day ->
              # For the end date, use :set_end state to check end-date rules
              # For dates in the middle, use :set_start to only check availability
              state_to_use =
                if day == checkout_date do
                  :set_end
                else
                  :set_start
                end

              !date_disabled?(
                day,
                assigns[:min],
                checkin_date,
                state_to_use,
                assigns[:max],
                assigns[:property],
                assigns[:today],
                assigns[:selected_booking_mode],
                assigns[:availability],
                assigns[:seasons]
              )
            end)

          all_dates_available
        end
      end
    end
  end

  defp unavailability_reason(
         day,
         min,
         checkin_date,
         state,
         max,
         property,
         today,
         selected_booking_mode,
         availability,
         seasons
       ) do
    # Check if date is before minimum
    if Date.compare(day, min) == :lt do
      "This date is in the past"
    else
      # Check if date is after maximum
      if max && Date.compare(day, max) == :gt do
        "This date is beyond the maximum booking date"
      else
        # Check season restrictions
        if property && today do
          unless is_date_selectable_cached?(property, day, today, seasons) do
            "This date is outside the booking season"
          else
            # Check availability
            day_availability = Map.get(availability, day)

            if day_availability do
              cond do
                day_availability.is_blacked_out ->
                  "This date is blacked out (maintenance or special event)"

                selected_booking_mode == :day && day_availability.has_buyout ->
                  "Full buyout is booked for this date"

                selected_booking_mode == :day && day_availability.spots_available == 0 ->
                  "No spots available (#{day_availability.day_bookings_count} of 12 guests already booked)"

                selected_booking_mode == :buyout && day_availability.has_buyout ->
                  "Full buyout is already booked for this date"

                selected_booking_mode == :buyout && day_availability.day_bookings_count > 0 ->
                  "Day bookings exist for this date (buyout not available)"

                Date.day_of_week(day) == 6 && property == :tahoe ->
                  "Check-in is not allowed on Saturdays"

                state == :set_end && checkin_date ->
                  nights = Date.diff(day, checkin_date)

                  # Get max nights from season for check-in date
                  max_nights =
                    if seasons && checkin_date do
                      season = Ysc.Bookings.Season.find_season_for_date(seasons, checkin_date)
                      Ysc.Bookings.Season.get_max_nights(season, property || :clear_lake)
                    else
                      # Fallback to property defaults
                      case property do
                        :tahoe -> 4
                        :clear_lake -> 30
                        _ -> 4
                      end
                    end

                  cond do
                    nights > max_nights ->
                      "Maximum stay is #{max_nights} nights"

                    nights < 1 ->
                      "Check-out date must be after check-in date"

                    Date.day_of_week(day) == 6 && property == :tahoe ->
                      "Check-out is not allowed on Saturdays"

                    true ->
                      # Check if range includes Saturday but not Sunday (Tahoe only)
                      if property == :tahoe do
                        date_range = Date.range(checkin_date, day) |> Enum.to_list()
                        day_of_weeks = Enum.map(date_range, &Date.day_of_week/1)
                        has_saturday = 6 in day_of_weeks
                        has_sunday = 7 in day_of_weeks

                        if has_saturday && not has_sunday do
                          "If your stay includes Saturday, it must also include Sunday"
                        else
                          "This date is unavailable"
                        end
                      else
                        "This date is unavailable"
                      end
                  end

                true ->
                  "This date is unavailable"
              end
            else
              # Date not in availability map (outside loaded range)
              "Availability data not loaded for this date"
            end
          end
        else
          if Date.day_of_week(day) == 6 && property == :tahoe do
            "Check-in is not allowed on Saturdays"
          else
            "This date is unavailable"
          end
        end
      end
    end
  end

  defp availability_display(day, selected_booking_mode, availability) do
    day_availability = Map.get(availability, day)

    if day_availability do
      case selected_booking_mode do
        :day ->
          if day_availability.is_blacked_out do
            "Blacked out"
          else
            if day_availability.has_buyout do
              "Buyout"
            else
              "#{day_availability.spots_available} spots"
            end
          end

        :buyout ->
          if day_availability.is_blacked_out do
            "Blacked out"
          else
            if day_availability.has_buyout do
              "Booked"
            else
              if day_availability.day_bookings_count > 0 do
                "Day bookings"
              else
                "Available"
              end
            end
          end

        _ ->
          ""
      end
    else
      ""
    end
  end

  defp today?(day), do: day == Date.utc_today()

  defp other_month?(day, current_date) do
    Date.beginning_of_month(day) != Date.beginning_of_month(current_date)
  end

  defp is_changeover_day?(day, availability) do
    case Map.get(availability, day) do
      %{is_changeover_day: true} = info ->
        IO.puts("""
        [DEBUG] is_changeover_day? for #{Date.to_string(day)}: true
          - has_checkout: #{Map.get(info, :has_checkout, false)}
          - has_checkin: #{Map.get(info, :has_checkin, false)}
          - is_changeover_day: #{Map.get(info, :is_changeover_day, false)}
        """)

        true

      info ->
        if info do
          IO.puts("""
          [DEBUG] is_changeover_day? for #{Date.to_string(day)}: false
            - has_checkout: #{Map.get(info, :has_checkout, false)}
            - has_checkin: #{Map.get(info, :has_checkin, false)}
            - is_changeover_day: #{Map.get(info, :is_changeover_day, false)}
          """)
        end

        false
    end
  end

  defp is_blacked_out?(day, availability) do
    case Map.get(availability, day) do
      %{is_blacked_out: true} -> true
      _ -> false
    end
  end

  defp has_both_checkout_and_checkin?(day, availability) do
    case Map.get(availability, day) do
      %{has_checkout: true, has_checkin: true} -> true
      _ -> false
    end
  end

  defp has_checkin?(day, availability) do
    case Map.get(availability, day) do
      %{has_checkin: true} = info ->
        IO.puts(
          "[DEBUG] has_checkin? #{Date.to_string(day)}: true (has_checkin: #{Map.get(info, :has_checkin, false)}, has_checkout: #{Map.get(info, :has_checkout, false)})"
        )

        true

      info ->
        if info do
          IO.puts(
            "[DEBUG] has_checkin? #{Date.to_string(day)}: false (has_checkin: #{Map.get(info, :has_checkin, false)}, has_checkout: #{Map.get(info, :has_checkout, false)})"
          )
        end

        false
    end
  end

  defp has_checkout?(day, availability) do
    case Map.get(availability, day) do
      %{has_checkout: true} = info ->
        IO.puts(
          "[DEBUG] has_checkout? #{Date.to_string(day)}: true (has_checkin: #{Map.get(info, :has_checkin, false)}, has_checkout: #{Map.get(info, :has_checkout, false)})"
        )

        true

      info ->
        if info do
          IO.puts(
            "[DEBUG] has_checkout? #{Date.to_string(day)}: false (has_checkin: #{Map.get(info, :has_checkin, false)}, has_checkout: #{Map.get(info, :has_checkout, false)})"
          )
        end

        false
    end
  end

  defp selected_range?(day, checkin_date, checkout_date) do
    if checkin_date && checkout_date do
      day in Date.range(checkin_date, checkout_date)
    else
      false
    end
  end

  defp in_hover_range?(day, checkin_date, hover_checkout_date) do
    if checkin_date && hover_checkout_date do
      day in Date.range(checkin_date, hover_checkout_date)
    else
      false
    end
  end

  defp selected_start?(day, checkin_date) do
    checkin_date && day == checkin_date
  end

  defp selected_end?(day, checkout_date) do
    checkout_date && day == checkout_date
  end

  defp week_rows(current_date) do
    first =
      current_date
      |> Date.beginning_of_month()
      |> Date.beginning_of_week(@week_start_at)

    last =
      current_date
      |> Date.end_of_month()
      |> Date.end_of_week(@week_start_at)

    Date.range(first, last)
    |> Enum.map(& &1)
    |> Enum.chunk_every(7)
  end

  defp format_date(date) do
    %{
      date: date,
      month: Calendar.strftime(date, "%B %Y"),
      week_rows: week_rows(date)
    }
  end
end
