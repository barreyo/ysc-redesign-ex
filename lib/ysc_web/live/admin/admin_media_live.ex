defmodule YscWeb.AdminMediaLive do
  use YscWeb, :live_view
  alias YscWeb.Components.GalleryComponent
  alias Ysc.Media
  alias YscWeb.S3.SimpleS3Upload

  @s3_bucket "media"

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

        <img src={@active_image.optimized_image_path} class="w-full object-cover rounded max-h-100" />
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

      <div class="flex justify-between py-6">
        <h1 class="text-2xl font-semibold leading-8 text-zinc-800">
          Media Library
        </h1>

        <.button phx-click={JS.navigate(~p"/admin/media/upload")}>
          <.icon name="hero-photo" class="w-5 h-5 -mt-1" /><span class="ms-1">Add New</span>
        </.button>
      </div>

      <section>
        <.live_component
          module={GalleryComponent}
          id="admin-media-gallery"
          images={@images}
          page={@page}
        />
      </section>
    </.side_menu>
    """
  end

  def mount(%{"id" => id}, _session, socket) do
    image = Media.fetch_image(id)
    image_uploader = Ysc.Accounts.get_user!(image.user_id)
    form = to_form(Media.Image.edit_image_changeset(image, %{}), as: "image")

    {:ok,
     socket
     |> assign(form: form)
     |> assign(:active_image, image)
     |> assign(:image_uploader, image_uploader)
     |> assign(:page, 1)
     |> assign(:images, images())
     |> assign(:active_page, :media), temporary_assigns: [form: nil]}
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Media")
     |> assign(:active_page, :media)
     |> assign(:page, 1)
     |> assign(:uploaded_files, [])
     |> assign(:images, images())
     |> allow_upload(:media_uploads,
       accept: ~w(.jpg .jpeg .png .gif .webp),
       max_entries: 10,
       external: &presign_upload/2
     )}
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
        raw_path = "#{details[:url]}/#{details[:key]}"

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
        {:ok, raw_path}
      end)

    {:noreply,
     update(socket, :uploaded_files, &(&1 ++ uploaded_files))
     |> assign(:page, 1)
     |> assign(:images, images())
     |> push_navigate(to: ~p"/admin/media")}
  end

  def handle_event("load-more", _, %{assigns: assigns} = socket) do
    {:noreply, assign(socket, page: assigns[:page] + 1) |> get_images()}
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

  defp get_images(%{assigns: %{page: page}} = socket) do
    socket
    |> assign(page: page)
    |> assign(images: images())
  end

  defp images do
    {:ok, images} = Media.list_images()
    images
  end

  defp error_to_string(:too_large), do: "Too large"
  defp error_to_string(:not_accepted), do: "You have selected an unacceptable file type"
  defp error_to_string(:too_many_files), do: "You have selected too many files"
end
