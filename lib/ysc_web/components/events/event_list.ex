defmodule YscWeb.EventsListLive do
  use YscWeb, :live_component

  alias Ysc.Events

  def render(assigns) do
    ~H"""
    <div>
      <div :if={@event_count > 0} class="grid grid-cols-1 md:grid-cols-3 gap-4 py-4">
        <div :for={{id, event} <- @streams.events} class="flex flex-col rounded" id={id}>
          <.link
            navigate={~p"/events/#{event.id}"}
            class="w-full hover:opacity-80 transition duration-200 transition-opacity ease-in-out"
          >
            <img
              src="http://media.s3.localhost.localstack.cloud:4566/media/01JEXWXEN68RCWEEQT6CRVXX7A_optimized.png"
              id={"image-#{event.id}"}
              loading="lazy"
              class="object-cover aspect-video rounded w-full object-center h-full max-h-[112rem]"
            />
          </.link>

          <div class="flex flex-col py-3 px-2 space-y-2">
            <div>
              <.badge type="red">Sold Out</.badge>
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

            <p class="text-sm text-pretty text-zinc-600"><%= event.description %></p>

            <div class="flex flex-row space-x-2 pt-2 items-center">
              <p class="text-sm font-semibold text-zinc-800">From $100.00</p>
              <.badge type="green">Limited 20% off</.badge>
            </div>
          </div>
        </div>
      </div>

      <div :if={@event_count == 0} class="flex flex-col items-center justify-center py-12">
        <p class="text-zinc-700">No upcoming events</p>
      </div>
    </div>
    """
  end

  def handle_info(
        {Ysc.Events, %Ysc.MessagePassingEvents.EventAdded{event: event} = message_event},
        socket
      ) do
    {:noreply, socket |> stream_insert(:events, event)}
  end

  def handle_info(
        {Ysc.Events, %Ysc.MessagePassingEvents.EventUpdated{event: event} = message_event},
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
