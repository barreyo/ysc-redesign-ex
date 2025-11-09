defmodule YscWeb.Components.DateRangePicker do
  @moduledoc """
  LiveView component for selecting date ranges.

  Provides an interactive calendar interface for selecting start and end dates.
  """
  use YscWeb, :live_component

  @week_start_at :sunday
  @fsm %{
    set_start: :set_end,
    set_end: :reset,
    reset: :set_start
  }
  @initial_state :set_start

  @impl true
  def render(assigns) do
    ~H"""
    <div class="date-range-picker">
      <.input field={@start_date_field} type="hidden" />
      <.input :if={@is_range?} field={@end_date_field} type="hidden" />
      <div class="relative w-full lg:w-80" phx-click="open-calendar" phx-target={@myself}>
        <.input
          name={"#{@id}_display_value"}
          required={@required}
          readonly
          type="text"
          class="w-full"
          label={@label}
          value={date_range_display(@range_start, @range_end)}
        />
        <.icon name="hero-calendar" class="absolute top-10 right-3 mt-0.5 flex text-zinc-600" />
      </div>

      <div
        :if={@calendar?}
        id={"#{@id}_calendar"}
        class="absolute z-50 w-96 shadow transition duration-300"
        phx-click-away="close-calendar"
        phx-target={@myself}
      >
        <div
          id="calendar_background"
          class="w-full bg-white rounded-md shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none p-3"
        >
          <div id="calendar_header" class="flex justify-between">
            <div id="button_left">
              <button
                type="button"
                phx-target={@myself}
                phx-click="prev-month"
                class="p-1.5 text-zinc-400 hover:text-zinc-500 transition duration-300"
              >
                <.icon name="hero-arrow-left" />
              </button>
            </div>

            <div id="current_month_year" class="self-center font-semibold">
              <%= @current.month %>
            </div>

            <div id="button_right">
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

          <div id="click_today" class="text-sm text-center">
            <.link phx-click="today" phx-target={@myself} class="text-zinc-700 hover:text-zinc-500">
              Today
            </.link>
          </div>

          <div
            id="calendar_weekdays"
            class="text-center mt-6 grid grid-cols-7 text-xs leading-6 text-zinc-800"
          >
            <div :for={week_day <- List.first(@current.week_rows)}>
              <%= Calendar.strftime(week_day, "%a") %>
            </div>
          </div>

          <div
            id={"calendar_days_#{String.replace(@current.month, " ", "-")}"}
            class="isolate mt-2 grid grid-cols-7 gap-px text-sm"
            phx-hook="DaterangeHover"
          >
            <button
              :for={day <- Enum.flat_map(@current.week_rows, & &1)}
              type="button"
              phx-target={@myself}
              phx-click="pick-date"
              phx-value-date={Calendar.strftime(day, "%Y-%m-%d") <> "T00:00:00Z"}
              disabled={date_disabled?(day, @min, @range_start, @state, @max)}
              class={[
                "calendar-day overflow-hidden py-1.5 h-10 rounded w-auto focus:z-10 w-full transition duration-300",
                today?(day) && "font-bold border border-zinc-400 rounded",
                date_disabled?(day, @min, @range_start, @state, @max) &&
                  "text-zinc-300 cursor-not-allowed opacity-50",
                !date_disabled?(day, @min, @range_start, @state, @max) &&
                  !before_min_date?(day, @min) &&
                  "hover:bg-blue-300 hover:border hover:border-blue-500",
                other_month?(day, @current.date) && "text-zinc-500",
                selected_range?(day, @range_start, @hover_range_end || @range_end) &&
                  "hover:bg-blue-500 bg-blue-500 text-zinc-100"
              ]}
            >
              <time
                class="mx-auto flex h-6 w-6 items-center justify-center rounded-full"
                datetime={Calendar.strftime(day, "%Y-%m-%d")}
              >
                <%= Calendar.strftime(day, "%d") %>
              </time>
            </button>
          </div>

          <div class="flex w-full justify-end mt-4">
            <.button type="button" phx-click="close-calendar" phx-target={@myself}>
              <%= select_button_text(@range_start, @range_end) %>
            </.button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    current_date = Date.utc_today()

    {
      :ok,
      socket
      |> assign(:calendar?, false)
      |> assign(:current, format_date(current_date))
      |> assign(:is_range?, true)
      |> assign(:range_start, nil)
      |> assign(:range_end, nil)
      |> assign(:hover_range_end, nil)
      |> assign(:readonly, false)
      |> assign(:disabled, false)
      |> assign(:selected_date, nil)
      |> assign(:form, nil)
    }
  end

  @impl true
  def update(assigns, socket) do
    range_start = from_str!(assigns.start_date_field.value)
    range_end = from_str!(end_value(assigns))

    # Preserve current date if we have one, otherwise use today
    current_date =
      if socket.assigns[:current] && socket.assigns.current[:date] do
        socket.assigns.current.date
      else
        Date.utc_today()
      end

    {
      :ok,
      socket
      |> assign(assigns)
      |> assign(:current, format_date(current_date))
      |> assign(:range_start, range_start)
      |> assign(:range_end, range_end)
      |> assign(:max, assigns[:max])
      # Only reset state if we don't have a range yet, otherwise preserve it
      |> assign(
        :state,
        if(range_start && range_end,
          do: socket.assigns[:state] || @initial_state,
          else: @initial_state
        )
      )
    }
  end

  @impl true
  def handle_event("open-calendar", _, socket) do
    {:noreply, socket |> assign(:calendar?, true)}
  end

  @impl true
  def handle_event("close-calendar", _, %{assigns: %{range_start: nil, range_end: nil}} = socket) do
    {:noreply, socket |> assign(:calendar?, false)}
  end

  @impl true
  def handle_event("close-calendar", _, socket) do
    [range_start, range_end] =
      [
        socket.assigns.range_start,
        socket.assigns.range_end || socket.assigns.range_start
      ]
      |> Enum.sort(&(DateTime.compare(&1, &2) != :gt))

    attrs = %{
      id: socket.assigns.id,
      start_date: range_start,
      end_date: range_end,
      form: socket.assigns.form
    }

    send(self(), {:updated_event, attrs})

    {
      :noreply,
      socket
      |> assign(:calendar?, false)
      |> assign(:range_start, range_start)
      |> assign(:range_end, range_end)
      |> assign(:end_date_field, set_field_value(socket.assigns, :end_date_field, range_end))
      |> assign(
        :start_date_field,
        set_field_value(socket.assigns, :start_date_field, range_start)
      )
      |> assign(:state, @initial_state)
    }
  end

  @impl true
  def handle_event("today", _, socket) do
    new_date = Date.utc_today()
    {:noreply, socket |> assign(:current, format_date(new_date))}
  end

  @impl true
  def handle_event("prev-month", _, socket) do
    new_date = new_date(socket.assigns)
    {:noreply, socket |> assign(:current, format_date(new_date))}
  end

  @impl true
  def handle_event("next-month", _, socket) do
    last_row = socket.assigns.current.week_rows |> List.last()
    new_date = next_month_new_date(socket.assigns.current.date, last_row)
    {:noreply, socket |> assign(:current, format_date(new_date))}
  end

  @impl true
  def handle_event("pick-date", %{"date" => date_str}, socket) do
    date_time = from_str!(date_str)
    date = DateTime.to_date(date_time)

    # Check minimum date
    if Date.compare(socket.assigns.min, date) == :gt do
      {:noreply, socket}
    else
      # Check maximum date (if set)
      if socket.assigns[:max] && Date.compare(date, socket.assigns.max) == :gt do
        {:noreply, socket}
      else
        # Validate date based on current state and rules
        if valid_date_selection?(socket, date) do
          ranges = calculate_date_ranges(socket.assigns.state, date_time)

          state =
            if socket.assigns.is_range? do
              @fsm[socket.assigns.state]
            else
              @initial_state
            end

          {
            :noreply,
            socket
            |> assign(ranges)
            |> assign(:state, state)
          }
        else
          {:noreply, socket}
        end
      end
    end
  end

  @impl true
  def handle_event("cursor-move", date_str, socket) do
    date = from_str!(date_str)
    day = DateTime.to_date(date)

    if Date.compare(socket.assigns.min, day) == :gt do
      {:noreply, socket}
    else
      # Only show hover if date is valid (not disabled)
      hover_range_end =
        case socket.assigns.state do
          :set_end ->
            if not date_disabled?(
                 day,
                 socket.assigns.min,
                 socket.assigns.range_start,
                 socket.assigns.state,
                 socket.assigns[:max]
               ) do
              date
            else
              nil
            end

          _ ->
            nil
        end

      {:noreply, socket |> assign(:hover_range_end, hover_range_end)}
    end
  end

  defp end_value(assigns) when is_map_key(assigns, :end_date_field) do
    case assigns.end_date_field.value do
      nil -> nil
      "" -> nil
      _ -> assigns.end_date_field.value
    end
  end

  defp end_value(assigns) when is_map_key(assigns, :to) do
    case assigns.to.value do
      nil -> nil
      "" -> nil
      _ -> assigns.to.value
    end
  end

  defp end_value(_), do: nil

  defp next_month_new_date(current_date, last_row) do
    last_row_last_day = last_row |> List.last()
    last_row_last_month = last_row_last_day |> Calendar.strftime("%B")
    last_row_first_month = last_row |> List.first() |> Calendar.strftime("%B")
    current_month = Calendar.strftime(current_date, "%B")
    next_month = next_month(last_row_first_month, last_row_last_month, last_row_last_day)

    case current_date in last_row && current_month == next_month do
      true ->
        current_date

      false ->
        current_date
        |> Date.end_of_month()
        |> Date.add(1)
    end
  end

  defp next_month(last_row_first_month, last_row_last_month, last_day)
       when last_row_first_month == last_row_last_month do
    last_day
    |> Date.end_of_month()
    |> Date.add(1)
    |> Calendar.strftime("%B")
  end

  defp next_month(_, last_day_of_last_week_month, _), do: last_day_of_last_week_month

  defp new_date(%{current: %{date: current_date, week_rows: week_rows}}) do
    current_date = current_date
    first_row = week_rows |> List.first()
    last_row = week_rows |> List.last()

    case current_date in last_row do
      true ->
        first_row
        |> List.last()
        |> Date.beginning_of_month()
        |> Date.add(-1)

      false ->
        current_date
        |> Date.beginning_of_month()
        |> Date.add(-1)
    end
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

  defp calculate_date_ranges(:set_start, date_time) do
    %{
      range_start: date_time,
      range_end: nil
    }
  end

  defp calculate_date_ranges(:set_end, date_time), do: %{range_end: date_time}

  defp calculate_date_ranges(:reset, _date_time) do
    %{
      range_start: nil,
      range_end: nil
    }
  end

  defp set_field_value(nil, _field, _value), do: nil

  defp set_field_value(assigns, field, value) when is_binary(value) do
    if Map.has_key?(assigns, field) and is_map(assigns[field]) do
      {:ok, value, _} = DateTime.from_iso8601(value)
      Map.put(assigns[field], :value, value)
    else
      nil
    end
  end

  defp set_field_value(assigns, field, value) do
    if Map.has_key?(assigns, field) and is_map(assigns[field]) do
      {:ok, value, _} = DateTime.from_iso8601(Date.to_string(value) <> "T00:00:00Z")
      Map.put(assigns[field], :value, value)
    else
      nil
    end
  end

  defp before_min_date?(day, min) do
    Date.compare(day, min) == :lt
  end

  # Check if a date should be disabled based on booking rules
  defp date_disabled?(day, min, range_start, state, max \\ nil) do
    # Always disable dates before minimum
    if Date.compare(day, min) == :lt do
      true
    else
      # Check if date is after maximum (if max is set)
      if max && Date.compare(day, max) == :gt do
        true
      else
        # Cannot check in on Saturday (day 6)
        if Date.day_of_week(day) == 6 do
          true
        else
          # When selecting end date (state is :set_end), validate against start date
          case state do
            :set_end when not is_nil(range_start) ->
              start_date = DateTime.to_date(range_start)
              nights = Date.diff(day, start_date)

              # Disable if:
              # 1. More than 4 nights
              # 2. Less than 1 night (end date before or same as start)
              # 3. Ends on Saturday (can never end on Saturday)
              # 4. If range includes Saturday, must end on Sunday or later
              cond do
                nights > 4 ->
                  true

                nights < 1 ->
                  true

                # Cannot end on Saturday
                Date.day_of_week(day) == 6 ->
                  true

                true ->
                  # Check if range includes Saturday - if so, must also include Sunday
                  date_range = Date.range(start_date, day) |> Enum.to_list()
                  day_of_weeks = Enum.map(date_range, &Date.day_of_week/1)
                  has_saturday = 6 in day_of_weeks
                  has_sunday = 7 in day_of_weeks

                  if has_saturday && not has_sunday do
                    # Range includes Saturday but not Sunday - invalid
                    true
                  else
                    false
                  end
              end

            _ ->
              false
          end
        end
      end
    end
  end

  # Validate date selection based on booking rules
  defp valid_date_selection?(socket, date) do
    # Check if date is after maximum (if max is set)
    if socket.assigns[:max] && Date.compare(date, socket.assigns.max) == :gt do
      false
    else
      # Cannot check in on Saturday (day 6)
      if Date.day_of_week(date) == 6 do
        false
      else
        case socket.assigns.state do
          :set_end when not is_nil(socket.assigns.range_start) ->
            start_date = DateTime.to_date(socket.assigns.range_start)
            nights = Date.diff(date, start_date)

            # Must be between 1 and 4 nights
            if nights < 1 or nights > 4 do
              false
            else
              # Cannot end on Saturday (day 6)
              if Date.day_of_week(date) == 6 do
                false
              else
                # If range includes Saturday, must also include Sunday
                date_range = Date.range(start_date, date) |> Enum.to_list()
                day_of_weeks = Enum.map(date_range, &Date.day_of_week/1)
                has_saturday = 6 in day_of_weeks
                has_sunday = 7 in day_of_weeks

                if has_saturday && not has_sunday do
                  # Range includes Saturday but not Sunday - invalid
                  false
                else
                  true
                end
              end
            end

          _ ->
            true
        end
      end
    end
  end

  defp today?(day), do: day == Date.utc_today()

  defp other_month?(day, current_date) do
    Date.beginning_of_month(day) != Date.beginning_of_month(current_date)
  end

  defp selected_range?(_day, nil, nil), do: false

  defp selected_range?(day, range_start, nil) do
    day == DateTime.to_date(range_start)
  end

  defp selected_range?(day, nil, range_end) do
    day == DateTime.to_date(range_end)
  end

  defp selected_range?(day, range_start, range_end) do
    start_date = DateTime.to_date(range_start)
    end_date = DateTime.to_date(range_end)
    day in Date.range(start_date, end_date)
  end

  defp format_date(date) do
    %{
      date: date,
      month: Calendar.strftime(date, "%B %Y"),
      week_rows: week_rows(date)
    }
  end

  defp from_str!(""), do: nil

  defp from_str!(date_time_str) when is_binary(date_time_str) do
    case DateTime.from_iso8601(date_time_str) do
      {:ok, date_time, _} -> date_time
      _ -> nil
    end
  end

  defp from_str!(date_time_str), do: date_time_str

  defp select_button_text(_start_date, nil) do
    "Select Date"
  end

  defp select_button_text(start_date, end_date) when start_date == end_date do
    "Select Date"
  end

  defp select_button_text(nil, nil), do: "Close"
  defp select_button_text("", nil), do: "Close"
  defp select_button_text(nil, ""), do: "Close"
  defp select_button_text("", ""), do: "Close"
  defp select_button_text(_start_date, _end_date), do: "Select Dates"

  defp date_range_display(start_date, nil) when start_date in [nil, ""] do
    "MM/DD/YYYY - MM/DD/YYYY"
  end

  defp date_range_display(start_date, end_date) when end_date in [nil, ""] do
    start_date_datetime = extract_date(start_date)
    Calendar.strftime(start_date_datetime, "%b %d, %Y")
  end

  defp date_range_display(start_date, end_date) do
    start_date_datetime = extract_date(start_date)
    end_date_datetime = extract_date(end_date)

    if start_date_datetime == end_date_datetime do
      Calendar.strftime(start_date_datetime, "%b %d, %Y")
    else
      "#{Calendar.strftime(start_date_datetime, "%b %d, %Y")} - #{Calendar.strftime(end_date_datetime, "%b %d, %Y")}"
    end
  end

  defp extract_date(input) when input in [nil, ""], do: Date.utc_today()

  defp extract_date(datetime_string) when is_binary(datetime_string) do
    datetime_string
    |> String.split("T")
    |> List.first()
    |> Date.from_iso8601!()
  end

  defp extract_date(%DateTime{} = datetime), do: DateTime.to_date(datetime)
  defp extract_date(%NaiveDateTime{} = datetime), do: NaiveDateTime.to_date(datetime)
  defp extract_date(%{calendar: Calendar.ISO} = datetime), do: datetime
end
