defmodule YscWeb.NewsLive do
  use YscWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="py-6 lg:py-10">
      <h2>Latest News</h2>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, socket}
  end
end
