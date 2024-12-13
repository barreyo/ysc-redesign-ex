defmodule YscWeb.EventsLive do
  use YscWeb, :live_view

  alias Ysc.Events

  def render(assigns) do
    ~H"""
    <div class="py-6 lg:py-10">
      <div class="max-w-screen-lg mx-auto flex flex-col px-4 space-y-4">
        <div class="w-full">
          <h2 class="text-2xl font-semibold leading-8">Latest Events</h2>
          <p class="text-zinc-700 max-w-2xl">
            Explore our upcoming events! New events are added regularly, so be sure to visit often and stay updated.
          </p>
        </div>

        <div class="pb-4">
          <.button>
            <.icon name="hero-calendar" class="-mt-1 me-2" />Subscribe to Event Calendar
          </.button>
        </div>

        <.live_component id="" module={YscWeb.EventsListLive} />
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Events")}
  end
end
