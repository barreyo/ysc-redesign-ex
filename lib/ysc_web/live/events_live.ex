defmodule YscWeb.EventsLive do
  use YscWeb, :live_view

  alias Ysc.Events

  @impl true
  def render(assigns) do
    ~H"""
    <div class="py-8 lg:py-10">
      <div class="max-w-screen-lg mx-auto flex flex-col px-4 space-y-6">
        <div class="prose prose-zinc">
          <h1>Upcoming Events</h1>
          <p>
            Explore our upcoming events! New events are added regularly, so be sure to visit often and stay updated.
          </p>
        </div>

        <.live_component id="event_list" module={YscWeb.EventsListLive} />
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Events.subscribe()
    end

    {:ok, socket |> assign(:page_title, "Events")}
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
end
