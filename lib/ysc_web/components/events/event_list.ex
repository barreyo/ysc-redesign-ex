defmodule YscWeb.EventsListLive do
  use YscWeb, :live_component

  alias Ysc.Events
  alias Ysc.Tickets

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div :if={@event_count > 0} class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 py-4">
        <div
          :for={{id, event} <- @streams.events}
          class={["flex flex-col rounded", event.state == :cancelled && "opacity-70"]}
          id={id}
        >
          <.link
            navigate={~p"/events/#{event.id}"}
            class="w-full hover:opacity-80 transition duration-200 transition-opacity ease-in-out"
          >
            <.live_component
              id={"event-cover-#{event.id}"}
              module={YscWeb.Components.Image}
              image_id={event.image_id}
              image={Map.get(event, :image)}
            />
          </.link>

          <div class="flex flex-col py-3 px-2 space-y-2">
            <div>
              <.event_badge
                event={event}
                sold_out={event_sold_out?(event)}
                selling_fast={Map.get(event, :selling_fast, false)}
              />
            </div>

            <.link
              navigate={~p"/events/#{event.id}"}
              class="text-2xl md:text-xl leading-6 font-semibold text-zinc-900 text-pretty"
            >
              <%= event.title %>
            </.link>

            <div class="space-y-0.5">
              <p class="font-semibold text-sm text-zinc-800">
                <%= Timex.format!(event.start_date, "{WDshort}, {Mshort} {D}") %><span :if={
                  event.start_time != nil && event.start_time != ""
                }>
              • <%= format_start_time(event.start_time) %>
            </span>
              </p>

              <p
                :if={event.location_name != nil && event.location_name != ""}
                class="text-zinc-800 text-sm"
              >
                <%= event.location_name %>
              </p>
            </div>

            <p class="text-sm text-pretty text-zinc-600 py-1"><%= event.description %></p>

            <div :if={event.state != :cancelled} class="flex flex-row space-x-2 pt-2 items-center">
              <p class={[
                "text-sm font-semibold",
                if event_sold_out?(event) do
                  "text-zinc-800 line-through"
                else
                  "text-zinc-800"
                end
              ]}>
                <%= event.pricing_info.display_text %>
              </p>
              <%!-- <.badge type="green">Limited 20% off</.badge> --%>
            </div>
          </div>
        </div>
      </div>

      <div :if={@event_count == 0} class="flex flex-col items-center justify-center py-12">
        <div class="text-center justify-center items-center w-full">
          <img
            class="w-60 mx-auto rounded-full"
            src="/images/vikings/viking_beer.png"
            alt="No upcoming events at the moment"
          />
          <.header class="pt-8">
            No upcoming events at the moment
            <:subtitle>Check back soon again! We're always adding new events.</:subtitle>
          </.header>
        </div>
      </div>
    </div>
    """
  end

  def handle_info(
        %{event: %Ysc.MessagePassingEvents.EventAdded{event: event}},
        socket
      ) do
    {:noreply, socket |> stream_insert(:events, event)}
  end

  def handle_info(
        %{event: %Ysc.MessagePassingEvents.EventUpdated{event: event}},
        socket
      ) do
    {:noreply, socket |> stream_insert(:events, event)}
  end

  @impl true
  def update(_assigns, socket) do
    event_count = Events.count_published_events()
    events = Events.list_upcoming_events()

    {:ok, socket |> stream(:events, events) |> assign(:event_count, event_count)}
  end

  defp format_start_time(time) when is_binary(time) do
    format_start_time(Timex.parse!(time, "{h12}:{m} {AM}"))
  end

  defp format_start_time(time) do
    Timex.format!(time, "{h12}:{m} {AM}")
  end

  defp event_sold_out?(event) do
    # Get event ID (handle both structs and maps)
    event_id = Map.get(event, :id) || Map.get(event, "id")

    # Use preloaded ticket_tiers if available (from batch loading), otherwise fetch
    ticket_tiers =
      case Map.get(event, :ticket_tiers) do
        nil -> Events.list_ticket_tiers_for_event(event_id)
        tiers -> tiers
      end

    # Filter out donation tiers - donations don't count toward "sold out" status
    non_donation_tiers =
      Enum.filter(ticket_tiers, fn tier ->
        tier_type = Map.get(tier, :type) || Map.get(tier, "type")
        tier_type != "donation" && tier_type != :donation
      end)

    # If there are no non-donation tiers, event is not sold out
    if Enum.empty?(non_donation_tiers) do
      false
    else
      # Filter out pre-sale tiers (tiers that haven't started selling yet)
      # We want to check tiers that are on sale OR have ended their sale
      relevant_tiers =
        Enum.filter(non_donation_tiers, fn tier ->
          # Include tiers that are on sale OR have ended their sale
          # Exclude tiers that haven't started their sale yet (pre-sale)
          tier_on_sale?(tier) || tier_sale_ended?(tier)
        end)

      # If there are no relevant tiers (all are pre-sale), event is not sold out
      if Enum.empty?(relevant_tiers) do
        false
      else
        # Check if all relevant non-donation tiers are sold out
        # A tier is sold out if available == 0 (unlimited tiers never count as sold out)
        all_tiers_sold_out =
          Enum.all?(relevant_tiers, fn tier ->
            available = get_available_quantity(tier)
            available == 0
          end)

        # Also check event capacity if max_attendees is set
        # (Note: This includes all tickets including donations, but if capacity is reached,
        #  all regular tickets are effectively sold out even if some tiers show availability)
        event_at_capacity =
          case Map.get(event, :max_attendees) || Map.get(event, "max_attendees") do
            nil ->
              false

            _ ->
              # Use preloaded ticket_count if available, otherwise query
              case Map.get(event, :ticket_count) do
                nil ->
                  Tickets.event_at_capacity?(event)

                ticket_count ->
                  max_attendees =
                    Map.get(event, :max_attendees) || Map.get(event, "max_attendees")

                  ticket_count >= max_attendees
              end
          end

        all_tiers_sold_out || event_at_capacity
      end
    end
  end

  defp tier_on_sale?(ticket_tier) do
    now = DateTime.utc_now()

    start_date = Map.get(ticket_tier, :start_date) || Map.get(ticket_tier, "start_date")
    end_date = Map.get(ticket_tier, :end_date) || Map.get(ticket_tier, "end_date")

    # Check if sale has started
    sale_started =
      case start_date do
        nil -> true
        sd -> DateTime.compare(now, sd) != :lt
      end

    # Check if sale has ended
    sale_ended =
      case end_date do
        nil -> false
        ed -> DateTime.compare(now, ed) == :gt
      end

    sale_started && !sale_ended
  end

  defp tier_sale_ended?(ticket_tier) do
    now = DateTime.utc_now()

    end_date = Map.get(ticket_tier, :end_date) || Map.get(ticket_tier, "end_date")

    case end_date do
      nil -> false
      ed -> DateTime.compare(now, ed) == :gt
    end
  end

  defp get_available_quantity(ticket_tier) do
    quantity = Map.get(ticket_tier, :quantity) || Map.get(ticket_tier, "quantity")

    sold_count =
      Map.get(ticket_tier, :sold_tickets_count) || Map.get(ticket_tier, "sold_tickets_count") || 0

    case quantity do
      # Unlimited
      nil ->
        :unlimited

      0 ->
        :unlimited

      qty ->
        available = qty - sold_count
        max(0, available)
    end
  end
end
