defmodule YscWeb.FileComponent do
  use YscWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="file-component">
      <%= for entry <- @file.entries do %>
        <div class="upload-entry">
          <YscWeb.Uploads.progress entry={entry} />
        </div>
      <% end %>
      <.live_file_input upload={@file} />
    </div>
    """
  end
end
