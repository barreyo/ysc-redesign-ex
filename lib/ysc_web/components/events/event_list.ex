defmodule YscWeb.EventsListLive do
  use YscWeb, :live_component

  alias Ysc.Events

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
            />
          </.link>

          <div class="flex flex-col py-3 px-2 space-y-2">
            <div>
              <.event_badge event={event} />
            </div>

            <.link
              navigate={~p"/events/#{event.id}"}
              class="text-2xl lg:text-lg leading-6 font-semibold text-zinc-900 text-pretty"
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
              <p class="text-sm font-semibold text-zinc-800">From $100.00</p>
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

  def update(assigns, socket) do
    event_count = Events.count_published_events()
    events = Events.list_upcoming_events()

    {:ok, socket |> stream(:events, events) |> assign(:event_count, event_count)}
  end

  defp format_start_time(time) when is_binary(time) do
    format_start_time(Timex.parse!(time, "{h24}:{m}"))
  end

  defp format_start_time(time) do
    Timex.format!(time, "{h24}:{m}")
  end
end
