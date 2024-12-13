defmodule YscWeb.Components.MapComponent do
  use YscWeb, :live_component

  def render(assigns) do
    ~H"""
    <div
      style="overflow: hidden"
      class="border border-zinc-300 rounded w-full h-80"
      phx-update="ignore"
      id="mapComponent"
    >
      <div class="w-full h-80" id="map" phx-hook="RadarMap"></div>
    </div>
    """
  end

  def mount(assigns, socket) do
    {:ok, socket |> assign(:lat, -122.4304095624007) |> assign(:lon, 37.76665168141606)}
  end

  def update(assigns, socket) do
    IO.inspect(assigns)
    IO.inspect(socket.assigns)

    {:ok,
     socket
     |> Phoenix.LiveView.push_event("add_marker", %{
       reference: "dance",
       lat: socket.assigns[:lat],
       lon: socket.assigns[:lon]
     })
     |> Phoenix.LiveView.push_event("position", %{})}
  end

  def handle_event("map-new-marker", params, socket) do
    IO.inspect(params)
    {:noreply, socket}
  end
end
