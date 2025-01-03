defmodule YscWeb.EventsLive do
  use YscWeb, :live_view

  alias Ysc.Events

  def render(assigns) do
    ~H"""
    <div class="py-6 lg:py-10">
      <div class="max-w-screen-lg mx-auto flex flex-col px-4 space-y-6">
        <div class="w-full">
          <h2 class="text-2xl font-semibold leading-8">Latest Events</h2>
          <p class="text-zinc-700 max-w-2xl">
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
  def handle_info({Ysc.Events, %_event{event: event} = base_event}, socket) do
    IO.inspect(base_event)
    send_update(YscWeb.EventsListLive, id: "event_list", event: base_event)
    {:noreply, socket}
  end
end
