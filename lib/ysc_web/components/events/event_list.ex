defmodule YscWeb.EventsListLive do
  use YscWeb, :live_component

  alias Ysc.Events
  alias Ysc.Tickets

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div :if={@event_count > 0} class="grid grid-cols-1 md:grid-cols-2 gap-8">
        <div :for={{id, event} <- @streams.events} id={id}>
          <.event_card
            event={event}
            sold_out={event_sold_out?(event)}
            selling_fast={Map.get(event, :selling_fast, false)}
          />
        </div>
      </div>

      <div :if={@event_count == 0} class="flex flex-col items-center justify-center py-12">
        <div class="text-center justify-center items-center w-full">
          <img
            class="w-60 mx-auto rounded-full"
            src={~p"/images/vikings/viking_beer.png"}
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
  def update(assigns, socket) do
    upcoming = Map.get(assigns, :upcoming, true)
    limit = Map.get(assigns, :limit)
    exclude_event_id = Map.get(assigns, :exclude_event_id)

    events =
      if upcoming do
        all_events =
          if limit,
            do: Events.list_upcoming_events(limit + 1),
            else: Events.list_upcoming_events()

        # Filter out the hero event if specified
        filtered_events =
          if exclude_event_id do
            Enum.reject(all_events, fn event -> event.id == exclude_event_id end)
          else
            all_events
          end

        # Apply limit after filtering
        if limit, do: Enum.take(filtered_events, limit), else: filtered_events
      else
        if limit, do: Events.list_past_events(limit), else: Events.list_past_events()
      end

    {:ok,
     socket
     |> stream(:events, events, reset: true)
     |> assign(:event_count, length(events))
     |> assign(:upcoming, upcoming)
     |> assign(:limit, limit)
     |> assign(:exclude_event_id, exclude_event_id)}
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
