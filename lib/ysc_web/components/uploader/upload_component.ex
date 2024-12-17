defmodule YscWeb.UploadComponent do
  use YscWeb, :live_component

  alias YscWeb.S3.SimpleS3Upload

  @s3_bucket "media"

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> allow_upload(:upload_component_file,
       accept: ~w(.jpg .jpeg .png .gif .webp),
       max_entries: 1,
       auto_upload: true
     )}
  end

  def update(assigns, socket) do
    {:ok, socket |> assign(assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <form
      id={"#{@id}-upload-form"}
      class="upload-component"
      action="#"
      phx-change="validate"
      phx-drop-target={@uploads.upload_component_file.ref}
      phx-submit="save"
      phx-target={@myself}
      data-user_id={123}
    >
      <.live_file_input upload={@uploads.upload_component_file} />
      <button type="submit">Upload</button>

      <section class="upload-entries">
        <h2>Preview</h2>
        <%= for entry <- @uploads.upload_component_file.entries do %>
          <div class="upload-entry__details">
            <% # <.live_img_preview> uses an internal hook to render a client-side image preview %>
            <.live_img_preview entry={entry} class="preview" />
            <% # review the handle_event("cancel") callback %>
            <a
              href="#"
              phx-click="cancel"
              phx-target={@myself}
              phx-value-ref={entry.ref}
              class="upload-entry__cancel"
            >
              &times;
            </a>
          </div>
        <% end %>
      </section>
    </form>
    """
  end

  @impl true
  def handle_event("validate", _, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :upload_component_file, ref)}
  end

  def handle_event("save", params, socket) do
    case YscWeb.Uploads.consume_entries(socket, :upload_component_file) do
      [] -> :ok
      [upload_path] -> hoist_upload(socket, upload_path)
    end

    {:noreply, socket}
  end

  defp hoist_upload(socket, upload_path) do
    send(self(), {__MODULE__, socket.assigns.id, upload_path})
    :ok
  end

  defp presign_upload(entry, socket) do
    uploads = socket.assigns.uploads
    key = "public/#{entry.client_name}"

    config = %{
      region: "us-west-1",
      access_key_id: System.fetch_env!("AWS_ACCESS_KEY_ID"),
      secret_access_key: System.fetch_env!("AWS_SECRET_ACCESS_KEY")
    }

    {:ok, fields} =
      SimpleS3Upload.sign_form_upload(config, @s3_bucket,
        key: key,
        content_type: entry.client_type,
        max_file_size: uploads[entry.upload_config].max_file_size,
        expires_in: :timer.hours(1)
      )

    meta = %{
      uploader: "S3",
      key: key,
      url: "http://media.s3.localhost.localstack.cloud:4566",
      fields: fields
    }

    {:ok, meta, socket}
  end
end
