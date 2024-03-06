defmodule YscWeb.AdminDashboardLive do
  use YscWeb, :live_view

  def render(assigns) do
    ~H"""
    <.side_menu active_page={@active_page}>
      <h1 class="text-2xl font-semibold leading-8 text-zinc-800 py-6">
        Overview
      </h1>
    </.side_menu>
    """
  end

  @spec mount(any(), any(), map()) :: {:ok, map()}
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:active_page, :dashboard) |> assign(:page_title, "Dashboard")}
  end
end
