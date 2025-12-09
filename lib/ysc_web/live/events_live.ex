defmodule YscWeb.EventsLive do
  use YscWeb, :live_view

  alias Ysc.Events

  @impl true
  def render(assigns) do
    ~H"""
    <div class="py-8 lg:py-10">
      <div class="max-w-screen-xl mx-auto flex flex-col px-4 space-y-6 lg:px-10">
        <!-- Upcoming Events Section -->
        <div class="prose prose-zinc">
          <h1>Upcoming Events</h1>
          <p>
            Explore our upcoming events! New events are added regularly, so be sure to visit often and stay updated.
          </p>
        </div>

        <.live_component id="event_list" module={YscWeb.EventsListLive} />
        <!-- Past Events Section (only show if there are past events) -->
        <%= if @past_events_exist do %>
          <div class="mt-16 max-w-screen-xl mx-auto flex flex-col space-y-6">
            <div class="prose prose-zinc">
              <h1>Past Events</h1>
            </div>

            <.live_component
              id="past_event_list"
              module={YscWeb.EventsListLive}
              upcoming={false}
              limit={@past_events_limit}
            />

            <%= if @past_events_limit < 50 do %>
              <% # Check if there are more events by trying to load one more than current limit %>
              <% has_more_events =
                Events.list_past_events(@past_events_limit + 1) |> length() > @past_events_limit %>
              <%= if has_more_events do %>
                <div class="text-center mt-8">
                  <.button phx-click="show_more_past_events">
                    Show More Past Events
                  </.button>
                </div>
              <% end %>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Events.subscribe()
    end

    # Check if there are any past events to determine whether to show the section
    past_events_exist = Events.list_past_events(1) |> Enum.any?()

    {:ok,
     socket
     |> assign(:page_title, "Events")
     |> assign(:past_events_exist, past_events_exist)
     |> assign(:past_events_limit, 10)}
  end

  @impl true
  def handle_info({Ysc.Events, %_event{event: _} = base_event}, socket) do
    send_update(YscWeb.EventsListLive, id: "event_list", event: base_event)
    {:noreply, socket}
  end

  # Handle ticket tier events - refresh the associated event in the list
  def handle_info(
        {Ysc.Events, %Ysc.MessagePassingEvents.TicketTierAdded{ticket_tier: ticket_tier}},
        socket
      ) do
    # Get the event and send an update to refresh it in the list
    case Events.get_event(ticket_tier.event_id) do
      nil ->
        {:noreply, socket}

      event ->
        event_updated = %Ysc.MessagePassingEvents.EventUpdated{event: event}
        send_update(YscWeb.EventsListLive, id: "event_list", event: event_updated)
        {:noreply, socket}
    end
  end

  def handle_info(
        {Ysc.Events, %Ysc.MessagePassingEvents.TicketTierUpdated{ticket_tier: ticket_tier}},
        socket
      ) do
    # Get the event and send an update to refresh it in the list
    case Events.get_event(ticket_tier.event_id) do
      nil ->
        {:noreply, socket}

      event ->
        event_updated = %Ysc.MessagePassingEvents.EventUpdated{event: event}
        send_update(YscWeb.EventsListLive, id: "event_list", event: event_updated)
        {:noreply, socket}
    end
  end

  def handle_info(
        {Ysc.Events, %Ysc.MessagePassingEvents.TicketTierDeleted{ticket_tier: ticket_tier}},
        socket
      ) do
    # Get the event and send an update to refresh it in the list
    case Events.get_event(ticket_tier.event_id) do
      nil ->
        {:noreply, socket}

      event ->
        event_updated = %Ysc.MessagePassingEvents.EventUpdated{event: event}
        send_update(YscWeb.EventsListLive, id: "event_list", event: event_updated)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("show_more_past_events", _params, socket) do
    current_limit = socket.assigns.past_events_limit
    # Increase by 10, max 50
    new_limit = min(current_limit + 10, 50)

    {:noreply, assign(socket, :past_events_limit, new_limit)}
  end
end
