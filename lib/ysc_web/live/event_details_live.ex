defmodule YscWeb.EventDetailsLive do
  use YscWeb, :live_view

  alias Ysc.Events

  def render(assigns) do
    ~H"""
    <div class="py-6 lg:py-10">
      <div class="max-w-screen-lg mx-auto flex flex-wrap px-4 space-y-6">
        <h2 class="text-2xl font-semibold leading-8">Event</h2>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Events")}
  end
end
