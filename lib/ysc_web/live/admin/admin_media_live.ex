defmodule YscWeb.AdminMediaLive do
  use YscWeb, :live_view
  alias YscWeb.Components.GalleryComponent
  alias Ysc.Media
  alias Ysc.S3Config
  alias YscWeb.S3.SimpleS3Upload

  def render(assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      email={@current_user.email}
      first_name={@current_user.first_name}
      last_name={@current_user.last_name}
      user_id={@current_user.id}
      most_connected_country={@current_user.most_connected_country}
    >
      <.modal
        :if={@live_action == :edit}
        id="update-image-modal"
        on_cancel={JS.navigate(~p"/admin/media")}
        show
      >
        <h2 class="text-2xl font-semibold leading-8 text-zinc-800 mb-4">
          Edit Image
        </h2>
        <!-- Image Version Tabs -->
        <div class="border-b border-zinc-200 mb-4">
          <nav class="-mb-px flex space-x-4" aria-label="Image Versions">
            <button
              phx-click="select-image-version"
              phx-value-version="optimized"
              class={[
                "whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm transition-colors",
                if(@selected_image_version == :optimized,
                  do: "border-blue-500 text-blue-600",
                  else: "border-transparent text-zinc-500 hover:text-zinc-700 hover:border-zinc-300"
                )
              ]}
            >
              Optimized
              <%= if @active_image.optimized_image_path do %>
                <span class="ml-1 text-xs text-zinc-400">✓</span>
              <% else %>
                <span class="ml-1 text-xs text-zinc-400">—</span>
              <% end %>
            </button>
            <button
              phx-click="select-image-version"
              phx-value-version="thumbnail"
              class={[
                "whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm transition-colors",
                if(@selected_image_version == :thumbnail,
                  do: "border-blue-500 text-blue-600",
                  else: "border-transparent text-zinc-500 hover:text-zinc-700 hover:border-zinc-300"
                )
              ]}
            >
              Thumbnail
              <%= if @active_image.thumbnail_path do %>
                <span class="ml-1 text-xs text-zinc-400">✓</span>
              <% else %>
                <span class="ml-1 text-xs text-zinc-400">—</span>
              <% end %>
            </button>
            <button
              phx-click="select-image-version"
              phx-value-version="raw"
              class={[
                "whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm transition-colors",
                if(@selected_image_version == :raw,
                  do: "border-blue-500 text-blue-600",
                  else: "border-transparent text-zinc-500 hover:text-zinc-700 hover:border-zinc-300"
                )
              ]}
            >
              Raw
              <%= if @active_image.raw_image_path do %>
                <span class="ml-1 text-xs text-zinc-400">✓</span>
              <% else %>
                <span class="ml-1 text-xs text-zinc-400">—</span>
              <% end %>
            </button>
          </nav>
        </div>
        <!-- Image Display -->
        <div class="mb-4">
          <%= if get_image_version_path(@active_image, @selected_image_version) do %>
            <img
              src={get_image_version_path(@active_image, @selected_image_version)}
              class="w-full object-cover rounded max-h-96"
              alt={@active_image.alt_text || @active_image.title || "Image"}
            />
            <div class="mt-2 text-xs text-zinc-500 space-y-1">
              <p>
                <strong>Version:</strong> <%= String.capitalize(
                  Atom.to_string(@selected_image_version)
                ) %>
              </p>
              <%= if @active_image.width && @active_image.height do %>
                <p>
                  <strong>Dimensions:</strong> <%= @active_image.width %> × <%= @active_image.height %> px
                </p>
              <% end %>
              <%= if @active_image.processing_state do %>
                <p>
                  <strong>Processing State:</strong> <%= String.capitalize(
                    Atom.to_string(@active_image.processing_state)
                  ) %>
                </p>
              <% end %>
              <p>
                <strong>Path:</strong>
                <span class="font-mono text-xs break-all">
                  <%= get_image_version_path(@active_image, @selected_image_version) %>
                </span>
              </p>
            </div>
          <% else %>
            <div class="w-full h-64 bg-zinc-100 rounded flex items-center justify-center">
              <div class="text-center">
                <.icon name="hero-photo" class="w-12 h-12 text-zinc-400 mx-auto mb-2" />
                <p class="text-sm text-zinc-500">
                  <%= String.capitalize(Atom.to_string(@selected_image_version)) %> version not available
                </p>
              </div>
            </div>
          <% end %>
        </div>

        <p class="leading-6 text-sm text-zinc-600 mt-2">
          Uploaded by <%= "#{String.capitalize(@image_uploader.first_name)} #{String.capitalize(@image_uploader.last_name)} (#{@image_uploader.email}) on #{Timex.format!(@image_uploader.inserted_at, "%Y-%m-%d", :strftime)}" %>
        </p>

        <.simple_form
          for={@form}
          id="edit_image_form"
          phx-submit="save-image"
          phx-change="validate-edit"
        >
          <.input field={@form[:title]} label="Title" />
          <.input field={@form[:alt_text]} label="Alt Text" />

          <div class="flex justify-end">
            <button
              class="rounded hover:bg-zinc-100 py-2 px-3 transition duration-200 ease-in-out text-sm font-semibold leading-6 text-zinc-800 active:text-zinc-800/80 mr-2"
              phx-click={JS.navigate(~p"/admin/media")}
            >
              Cancel
            </button>
            <.button type="submit">
              Update Image
            </.button>
          </div>
        </.simple_form>
      </.modal>

      <.modal
        :if={@live_action == :upload}
        id="add-images-modal"
        on_cancel={JS.navigate(~p"/admin/media")}
        show
      >
        <h2 class="text-2xl font-semibold leading-8 text-zinc-800 mb-4">
          Upload new images
        </h2>
        <div class="w-full">
          <form id="upload-form" phx-submit="save" phx-change="validate">
            <label
              class="flex p-6 flex-col items-center justify-center w-full min-h-72 border-2 border-zinc-300 border-dashed rounded-lg cursor-pointer bg-zinc-50 hover:bg-zinc-100"
              phx-drop-target={@uploads.media_uploads.ref}
            >
              <.live_file_input upload={@uploads.media_uploads} class="hidden" />

              <div class="flex flex-row flex-wrap gap-2">
                <%= for entry <- @uploads.media_uploads.entries do %>
                  <article class="upload-entry">
                    <figure class="w-28 group relative">
                      <button
                        type="button"
                        phx-click="cancel-upload"
                        phx-value-ref={entry.ref}
                        aria-label="cancel"
                      >
                        <div class="hidden group-hover:block absolute top-1/2 left-1/2 transform -translate-x-1/2 -translate-y-1/2 text-red-500 z-10">
                          <.icon name="hero-x-circle" class="w-10 h-10" />
                        </div>
                        <.live_img_preview
                          entry={entry}
                          class="group-hover:blur"
                          width="120"
                          height="120"
                        />
                        <figcaption class="text-sm truncate overflow-hidden bg-zinc-100 text-zinc-600 w-28 z-8 absolute inset-x-0 bottom-0 py-1">
                          <%= entry.client_name %>
                        </figcaption>
                      </button>
                    </figure>

                    <%!-- Phoenix.Component.upload_errors/2 returns a list of error atoms --%>
                    <%= for err <- upload_errors(@uploads.media_uploads, entry) do %>
                      <p class="alert alert-danger text-sm text-red-600 font-semibold mt-1">
                        <.icon name="hero-exclamation-circle" class="-mt-0.5 h-5 w-5" /> <%= error_to_string(
                          err
                        ) %>
                      </p>
                    <% end %>
                  </article>
                <% end %>
              </div>

              <%!-- Phoenix.Component.upload_errors/1 returns a list of error atoms --%>
              <%= for err <- upload_errors(@uploads.media_uploads) do %>
                <p class="alert alert-danger text-sm text-red-600 font-semibold mt-1">
                  <.icon name="hero-exclamation-circle" class="-mt-0.5 h-5 w-5" /> <%= error_to_string(
                    err
                  ) %>
                </p>
              <% end %>

              <div
                :if={length(@uploads.media_uploads.entries) == 0}
                class="flex flex-col items-center justify-center pt-5 pb-6"
              >
                <.icon name="hero-cloud-arrow-up" class="w-8 h-10 mb-4 text-zinc-500" />
                <p class="mb-2 text-sm text-zinc-500">
                  <span class="font-semibold">Click to upload</span> or drag and drop
                </p>
                <p class="text-xs text-zinc-500">
                  SVG, PNG, JPG, JPEG or GIF
                </p>
              </div>
            </label>

            <div class="w-full flex justify-end pt-4">
              <.button
                type="submit"
                aria-disabled={length(@uploads.media_uploads.entries) == 0}
                disabled={length(@uploads.media_uploads.entries) == 0}
              >
                Upload
              </.button>
            </div>
          </form>
        </div>
      </.modal>

      <div class="flex justify-between items-center py-6 border-b border-zinc-200">
        <div>
          <h1 class="text-2xl font-semibold leading-8 text-zinc-800">
            Media Library
          </h1>
          <p :if={@media_count > 0} class="text-sm text-zinc-600 mt-1">
            <%= @media_count %> <%= if @media_count == 1, do: "image", else: "images" %>
          </p>
        </div>

        <.button phx-click={JS.navigate(~p"/admin/media/upload")}>
          <.icon name="hero-photo" class="w-5 h-5 -mt-1" /><span class="ms-1">New Image</span>
        </.button>
      </div>

      <section class="py-6">
        <.live_component
          :if={@media_count > 0}
          module={GalleryComponent}
          id="admin-media-gallery"
          images={@streams.images}
          page={@page}
        />

        <div :if={@media_count == 0} class="mx-auto py-20 text-center">
          <div class="flex flex-col items-center">
            <.icon name="hero-photo" class="w-16 h-16 text-zinc-300 mb-4" />
            <p class="text-lg font-medium text-zinc-700 mb-2">No images yet</p>
            <p class="text-sm text-zinc-500 mb-6">Upload your first image to get started</p>
            <.button phx-click={JS.navigate(~p"/admin/media/upload")}>
              <.icon name="hero-cloud-arrow-up" class="w-5 h-5 -mt-1" />
              <span class="ms-1">
                Upload Image
              </span>
            </.button>
          </div>
        </div>
      </section>
    </.side_menu>
    """
  end

  def mount(%{"id" => id}, _session, socket) do
    image = Media.fetch_image(id)
    image_uploader = Ysc.Accounts.get_user!(image.user_id)
    form = to_form(Media.Image.edit_image_changeset(image, %{}), as: "image")
    media_count = Media.count_images()

    {:ok,
     socket
     |> assign(:media_count, media_count)
     |> assign(:page_title, "Media")
     |> assign(form: form)
     |> assign(:active_image, image)
     |> assign(:image_uploader, image_uploader)
     |> assign(:selected_image_version, :optimized)
     |> assign(page: 1, per_page: 20)
     |> paginate_images(1)
     |> assign(:active_page, :media), temporary_assigns: [form: nil]}
  end

  def mount(_params, _session, socket) do
    media_count = Media.count_images()

    {:ok,
     socket
     |> assign(:media_count, media_count)
     |> assign(:page_title, "Media")
     |> assign(:active_page, :media)
     |> assign(page: 1, per_page: 20)
     |> assign(:uploaded_files, [])
     |> paginate_images(1)
     |> allow_upload(:media_uploads,
       accept: ~w(.jpg .jpeg .png .gif .webp),
       max_entries: 10,
       external: &presign_upload/2
     )}
  end

  defp paginate_images(socket, new_page) when new_page >= 1 do
    %{per_page: per_page} = socket.assigns
    images = Media.list_images((new_page - 1) * per_page, per_page)

    # Replace the entire stream with new page's images to prevent shifting
    # Use reset: true to ensure the stream is properly reset and items don't shift
    socket
    |> assign(end_of_timeline?: length(images) < per_page)
    |> assign(:page, new_page)
    |> stream(:images, images, reset: true)
  end

  def handle_event("next-page", _, socket) do
    {:noreply, paginate_images(socket, socket.assigns.page + 1)}
  end

  def handle_event("prev-page", %{"_overran" => true}, socket) do
    {:noreply, paginate_images(socket, 1)}
  end

  def handle_event("prev-page", _, socket) do
    if socket.assigns.page > 1 do
      {:noreply, paginate_images(socket, socket.assigns.page - 1)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :media_uploads, ref)}
  end

  def handle_event("save", _params, socket) do
    uploader = socket.assigns[:current_user]

    uploaded_files =
      consume_uploaded_entries(socket, :media_uploads, fn details, _entry ->
        raw_path = S3Config.object_url(details[:key])

        {:ok, new_image} =
          Media.add_new_image(
            %{
              raw_image_path: URI.encode(raw_path),
              user_id: uploader.id,
              upload_data: details
            },
            uploader
          )

        %{id: new_image.id} |> YscWeb.Workers.ImageProcessor.new() |> Oban.insert()
        {:ok, new_image}
      end)

    updated_socket =
      Enum.reduce(uploaded_files, socket, fn x, acc ->
        acc |> stream_insert(:images, x, at: 0)
      end)

    {:noreply,
     update(updated_socket, :uploaded_files, &(&1 ++ uploaded_files))
     |> push_navigate(to: ~p"/admin/media")}
  end

  def handle_event("validate-edit", %{"image" => image_params}, socket) do
    form_data =
      Media.Image.edit_image_changeset(
        socket.assigns[:active_image],
        image_params
      )

    {:noreply,
     socket
     |> assign(form: to_form(Map.put(form_data, :action, :validate), as: "image"))}
  end

  def handle_event("save-image", %{"image" => image_params}, socket) do
    current_user = socket.assigns[:current_user]
    active_image = socket.assigns[:active_image]

    Media.update_image(active_image, image_params, current_user)

    {:noreply, socket |> push_navigate(to: ~p"/admin/media")}
  end

  def handle_event("select-image-version", %{"version" => version}, socket) do
    version_atom =
      case version do
        "thumbnail" -> :thumbnail
        "optimized" -> :optimized
        "raw" -> :raw
        _ -> :thumbnail
      end

    {:noreply, assign(socket, :selected_image_version, version_atom)}
  end

  defp presign_upload(entry, socket) do
    uploads = socket.assigns.uploads
    key = "public/#{entry.client_name}"

    config = %{
      region: S3Config.region(),
      access_key_id: S3Config.aws_access_key_id(),
      secret_access_key: S3Config.aws_secret_access_key()
    }

    {:ok, fields} =
      SimpleS3Upload.sign_form_upload(config, S3Config.bucket_name(),
        key: key,
        content_type: entry.client_type,
        max_file_size: uploads[entry.upload_config].max_file_size,
        expires_in: :timer.hours(1)
      )

    meta = %{
      uploader: "S3",
      key: key,
      url: S3Config.upload_url(),
      fields: fields
    }

    {:ok, meta, socket}
  end

  defp error_to_string(:too_large), do: "Too large"
  defp error_to_string(:not_accepted), do: "You have selected an unacceptable file type"
  defp error_to_string(:too_many_files), do: "You have selected too many files"

  defp error_to_string(:external_client_failure) do
    "Upload failed: The file could not be uploaded to storage. " <>
      "This may be due to network issues, CORS configuration, or invalid credentials. " <>
      "Please check the browser console for more details."
  end

  defp error_to_string(_), do: "An error occurred"

  # Helper function to get a specific image version path
  defp get_image_version_path(%Media.Image{} = image, :thumbnail) do
    image.thumbnail_path
  end

  defp get_image_version_path(%Media.Image{} = image, :optimized) do
    image.optimized_image_path
  end

  defp get_image_version_path(%Media.Image{} = image, :raw) do
    image.raw_image_path
  end

  defp get_image_version_path(_, _), do: nil
end
