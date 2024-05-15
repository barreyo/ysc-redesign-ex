defmodule YscWeb.AdminPostEditorLive do
  use YscWeb, :live_view

  alias HtmlSanitizeEx.Scrubber
  alias YscWeb.S3.SimpleS3Upload

  alias Ysc.Media
  alias Ysc.Posts.Post
  alias Ysc.Posts

  @save_debounce_timeout 2000
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
        :if={@live_action == :preview}
        show={true}
        fullscreen={true}
        id="admin-post-preview-modal"
        on_cancel={JS.navigate(~p"/admin/posts/#{@post_id}")}
      >
        <div class="flex flex-col h-[86vh]">
          <ul class="flex flex-wrap items-center justify-center pb-4">
            <li>
              <button
                type="button"
                class={[
                  "flex-none rounded hover:bg-zinc-100 px-3 py-2 transition ease-in-out duration-200 rounded text-zinc-800 mr-3",
                  @preview_device == :phone && "bg-zinc-100"
                ]}
                phx-click="phone-preview"
              >
                <.icon name="hero-device-phone-mobile" class="w-8 h-8" />
                <span class="sr-only">Phone preview</span>
              </button>
            </li>
            <li>
              <button
                type="button"
                class={[
                  "flex-none rounded hover:bg-zinc-100 px-3 py-2 transition ease-in-out duration-200 rounded text-zinc-800 mr-3",
                  @preview_device == :tablet && "bg-zinc-100"
                ]}
                phx-click="tablet-preview"
              >
                <.icon name="hero-device-tablet" class="w-8 h-8 " />
                <span class="sr-only">Tablet preview</span>
              </button>
            </li>
            <li>
              <button
                type="button"
                class={[
                  "flex-none rounded hover:bg-zinc-100 px-3 py-2 transition ease-in-out duration-200 rounded text-zinc-800 mr-3",
                  @preview_device == :computer && "bg-zinc-100"
                ]}
                phx-click="computer-preview"
              >
                <.icon name="hero-computer-desktop" class="w-8 h-8 " />
                <span class="sr-only">Desktop preview</span>
              </button>
            </li>
          </ul>

          <div class={[
            "w-full bg-blue-100 h-full rounded border border-1 border-zinc-300",
            (@preview_device == :phone || @preview_device == :tablet) && "py-20"
          ]}>
            <.phone_mockup :if={@preview_device == :phone} class="m-auto">
              <iframe
                src={"/posts/#{@post_id}"}
                class={[
                  "h-full w-full"
                ]}
              >
              </iframe>
            </.phone_mockup>

            <.tablet_mockup :if={@preview_device == :tablet} class="m-auto">
              <iframe
                src={"/posts/#{@post_id}"}
                class={[
                  "h-full w-full"
                ]}
              >
              </iframe>
            </.tablet_mockup>

            <iframe
              :if={@preview_device == :computer}
              src={"/posts/#{@post_id}"}
              class={[
                "h-full w-full"
              ]}
            >
            </iframe>
          </div>
        </div>
      </.modal>

      <.modal
        :if={@live_action == :settings}
        show={true}
        fullscreen={false}
        id="admin-post-settings-modal"
        on_cancel={JS.navigate(~p"/admin/posts/#{@post_id}")}
      >
        <div class="flex flex-col">
          <h2 class="text-2xl font-semibold leading-8 text-zinc-800 mb-4">Post Settings</h2>

          <div class="rounded border border-1 border-zinc-100 px-3 py-4">
            <p>Featured Image</p>
          </div>
        </div>
      </.modal>

      <form id="file-upload-form" phx-submit="save-image">
        <.live_file_input upload={@uploads.uploads} class="hidden" />
      </form>

      <.form :let={_f} for={@form} id="edit_post_form" phx-submit="save" phx-change="post-update">
        <div class="w-full flex flex-row justify-between">
          <div class="w-full flex flex-row items-center align-middle mt-4">
            <.input
              type="text-growing"
              field={@form[:title]}
              phx-debounce="500"
              growing_field_size="large"
              class="input-element mt-2 block w-full font-extrabold text-3xl outline-none border-none focus:border focus:border-1 focus:border-zinc-200 rounded text-zinc-900 focus:border-1 focus:border-zinc-400 focus:outline focus:outline-zinc-200 focus:ring-0 leading-6 focus:border-zinc-400"
            />

            <.badge type={post_state_to_badge_style(@post.state)} class="mt-3 ml-3">
              <%= String.capitalize("#{@post.state}") %>
            </.badge>

            <p class={"text-sm text-zinc-600 transition duration-200 ease-in-out align-middle inline-block items-center px-1 mt-4 #{if @saving? == true, do: "opacity-100", else: "opacity-0"}"}>
              <span>
                <.icon name="hero-arrow-path" class="w-4 h-4 -mt-0.5 animate-spin mr-1" />
              </span>
              Saving...
            </p>
          </div>

          <div class="flex flex-row align-baseline items-end">
            <.button
              :if={@post.state == :draft}
              class="hidden lg:block w-28 mr-3"
              type="button"
              phx-click="publish-post"
            >
              <.icon name="hero-document-arrow-up" class="w-5 h-5 -mt-1" />
              <span class="me-1">Publish</span>
            </.button>

            <.button
              :if={@post.state == :deleted}
              color="green"
              class="hidden lg:block w-28 mr-3"
              type="button"
              phx-click="restore-post"
            >
              <.icon name="hero-cloud-arrow-up" class="w-5 h-5 -mt-1" />
              <span class="me-1">Restore</span>
            </.button>

            <button
              type="button"
              class="hidden lg:block flex-none rounded hover:bg-zinc-100 px-3 py-2 transition ease-in-out duration-200 rounded text-zinc-800 mr-3"
              phx-click={JS.navigate(~p"/admin/posts/#{@post_id}/preview")}
            >
              <.icon name="hero-computer-desktop" class="w-5 h-5 -mt-1" />
              <span class="sr-only">Preview post</span>
            </button>

            <.dropdown
              id="edit-post-more"
              right={true}
              class="text-zinc-800 hover:bg-zinc-100 hover:text-black"
            >
              <:button_block>
                <.icon name="hero-ellipsis-vertical" class="w-6 h-6" />
              </:button_block>

              <div class="w-full divide-y divide-zinc-100 text-sm text-zinc-700">
                <ul class="block lg:hidden py-2">
                  <li>
                    <.link
                      navigate={~p"/admin/posts/#{@post_id}/preview"}
                      class="block px-4 py-2 transition ease-in-out hover:bg-zinc-100 duration-400"
                    >
                      <.icon name="hero-document-arrow-up" class="w-5 h-5 -mt-1 mr-1" />
                      <span>Publish</span>
                    </.link>
                  </li>
                  <li>
                    <.link
                      navigate={~p"/admin/posts/#{@post_id}/preview"}
                      class="block px-4 py-2 transition ease-in-out hover:bg-zinc-100 duration-400"
                    >
                      <.icon name="hero-computer-desktop" class="w-5 h-5 -mt-1 mr-1" />
                      <span>Preview</span>
                    </.link>
                  </li>
                </ul>

                <ul class="py-2 text-sm font-medium text-zinc-800 py-1">
                  <li>
                    <li>
                      <.link
                        navigate={~p"/admin/posts/#{@post_id}/settings"}
                        class="block px-4 py-2 transition ease-in-out hover:bg-zinc-100 duration-400"
                      >
                        <.icon name="hero-adjustments-horizontal" class="w-5 h-5 -mt-1 mr-1" />
                        <span>Post Settings</span>
                      </.link>
                    </li>
                  </li>

                  <li class="block py-2 px-3 transition text-red-600 ease-in-out duration-200 hover:bg-zinc-100">
                    <button type="button" class="w-full text-left px-1" phx-click="delete-post">
                      <.icon name="hero-trash" class="w-5 h-5 -mt-1" />
                      <span>Delete Post</span>
                    </button>
                  </li>
                </ul>
              </div>
            </.dropdown>
          </div>
        </div>

        <div class="text-sm text-zinc-500 leading-6 py-1 flex flex-row align-baseline items-end">
          <span>
            <.link href={~p"/posts/#{@post.url_name}"} target="_blank">
              <.icon name="hero-arrow-top-right-on-square" class=" text-zinc-800 w-4 h-4 -mt-1 mr-2" />
            </.link>
          </span>
          <span class="pt-2 mr-1 hidden lg:block"><%= "#{YscWeb.Endpoint.url()}/posts/" %></span>
          <span>
            <.input
              type="text-growing"
              field={@form[:url_name]}
              class="input-element mt-2 block w-full text-sm outline-none border-none focus:border focus:border-1 focus:border-zinc-200 rounded text-blue-600 focus:border-1 focus:border-zinc-400 focus:outline focus:outline-zinc-200 focus:ring-0 leading-6 focus:border-zinc-400"
            />
          </span>
        </div>
      </.form>

      <.form :let={_f} for={@form} id="trix-editor-form">
        <div class="prose prose-zinc prose-base prose-a:text-blue-600 max-w-none mx-auto py-8">
          <.input type="hidden" id="post[raw_body]" field={@form[:raw_body]} phx-hook="TrixHook" />
          <div id="richtext" phx-update="ignore">
            <trix-editor
              input="post[raw_body]"
              class="trix-content block mt-8 max-w-2xl mx-auto px-8 py-8 bg-white border-0 focus:ring-0 text-wrap"
              placeholder="Write something delightful and nice..."
            >
            </trix-editor>
          </div>
        </div>
      </.form>
    </.side_menu>
    """
  end

  def mount(%{"id" => id} = _params, _session, socket) do
    post = Posts.get_post!(id)
    update_post_changeset = Post.update_post_changeset(post, %{})

    YscWeb.Endpoint.subscribe("post_saved:#{id}")

    {:ok,
     socket
     |> assign(:page_title, post.title)
     |> assign(:active_page, :news)
     |> assign(:saving?, false)
     |> assign(:post_id, post.id)
     |> assign(:post, post)
     |> assign(:preview_device, :computer)
     |> assign(:uploaded_files, [])
     |> assign(form: to_form(update_post_changeset, as: "post"))
     |> allow_upload(:uploads,
       accept: :any,
       max_entries: 10,
       external: &presign_upload/2,
       auto_uploads: true
     )}
  end

  @spec handle_event(<<_::32, _::_*8>>, any(), atom() | map()) :: {:noreply, map()}
  def handle_event("post-update", %{"post" => values}, socket) do
    post = socket.assigns[:post]

    # Ensure UI is not cleared out
    updated_values =
      Map.put_new(values, "title", post.title) |> Map.put_new("url_name", post.url_name)

    changeset = Post.update_post_changeset(%Post{}, updated_values)
    form_socket = assign_form(socket, Map.put(changeset, :action, :validate))

    # Don't save too often. We wait a little and only save once user has stopped
    # typing or removes focus from the field. Even if user navigates away from the page
    # this function runs in a separate process and will complete.
    Debouncer.delay(
      socket.assigns[:post_id],
      fn ->
        # Only run DB validation if it has actually changed
        opts =
          if post.url_name != Map.get(values, "url_name", "") do
            [validate_url_name: true]
          else
            []
          end

        # Need to scrub if html body has changed
        html_scrubbed_values =
          if Map.has_key?(values, "raw_body") do
            Map.put(
              values,
              "rendered_body",
              Scrubber.scrub(Map.get(values, "raw_body"), Scrubber.BasicHTML)
            )
          else
            values
          end

        Posts.update_post(
          %Post{id: socket.assigns[:post_id]},
          html_scrubbed_values,
          socket.assigns[:current_user],
          opts
        )

        YscWeb.Endpoint.broadcast(
          "post_saved:#{socket.assigns[:post_id]}",
          "saved",
          socket.assigns[:post_id]
        )
      end,
      @save_debounce_timeout
    )

    {:noreply, form_socket |> assign(:saving?, true)}
  end

  def handle_event("save", %{"post" => _values} = req, socket) do
    handle_event("post-update", req, socket)
  end

  def handle_event("editor-update", params, socket) do
    handle_event("post-update", %{"post" => params}, socket)
  end

  def handle_event("publish-post", _params, socket) do
    post = socket.assigns[:post]

    res =
      Posts.update_post(
        post,
        %{state: :published, published_on: Timex.now()},
        socket.assigns[:current_user]
      )

    case res do
      {:ok, new_post} ->
        {:noreply,
         socket
         |> assign(:post, new_post)
         |> put_flash(:info, "The post was published!")
         |> redirect(to: ~p"/admin/posts/#{post.id}")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Something went wrong")
         |> redirect(to: ~p"/admin/posts")}
    end
  end

  def handle_event("restore-post", _params, socket) do
    post = socket.assigns[:post]

    res =
      Posts.update_post(
        post,
        %{state: :draft, published_on: nil, deleted_on: nil, featured_post: false},
        socket.assigns[:current_user]
      )

    case res do
      {:ok, new_post} ->
        {:noreply,
         socket
         |> assign(:post, new_post)
         |> put_flash(:info, "The post recovered.")
         |> redirect(to: ~p"/admin/posts/#{post.id}")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Something went wrong")
         |> redirect(to: ~p"/admin/posts")}
    end
  end

  def handle_event("delete-post", _params, socket) do
    post = socket.assigns[:post]

    res =
      Posts.update_post(
        post,
        %{state: :deleted, deleted_on: Timex.now(), published_on: nil, featured_post: false},
        socket.assigns[:current_user]
      )

    case res do
      {:ok, new_post} ->
        {:noreply,
         socket
         |> assign(:post, new_post)
         |> put_flash(:info, "The post was deleted.")
         |> redirect(to: ~p"/admin/posts")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Something went wrong")
         |> redirect(to: ~p"/admin/posts")}
    end
  end

  def handle_event("phone-preview", _params, socket) do
    {:noreply, assign(socket, :preview_device, :phone)}
  end

  def handle_event("tablet-preview", _params, socket) do
    {:noreply, assign(socket, :preview_device, :tablet)}
  end

  def handle_event("computer-preview", _params, socket) do
    {:noreply, assign(socket, :preview_device, :computer)}
  end

  def handle_event("validate", params, socket) do
    IO.inspect(params)
    {:noreply, socket}
  end

  def handle_event("save-image", params, socket) do
    uploader = socket.assigns[:current_user]

    IO.inspect(socket)
    IO.inspect(params)

    uploaded_files =
      consume_uploaded_entries(socket, :uploads, fn details, _entry ->
        raw_path = "#{details[:url]}/#{details[:key]}"

        IO.inspect(details)

        {:ok, new_image} =
          Media.add_new_image(
            %{
              raw_image_path: raw_path,
              user_id: uploader.id,
              upload_data: details
            },
            uploader
          )

        %{id: new_image.id} |> YscWeb.Workers.ImageProcessor.new() |> Oban.insert()
        {:ok, raw_path}
      end)

    IO.puts("DDDDD")
    IO.inspect(uploaded_files)

    {:noreply,
     update(socket, :uploaded_files, &(&1 ++ uploaded_files))
     |> push_event("media-upload-complete", %{image_url: "YOOO IMAGE ID"})}
  end

  @spec handle_info(Phoenix.Socket.Broadcast.t(), %{
          :assigns => nil | maybe_improper_list() | map(),
          optional(any()) => any()
        }) :: {:noreply, map()}
  def handle_info(%Phoenix.Socket.Broadcast{event: "saved"}, socket) do
    {:noreply,
     assign(socket, :saving?, false) |> assign(:post, Posts.get_post!(socket.assigns[:post_id]))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "post")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
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

  defp post_state_to_badge_style(:draft), do: "yellow"
  defp post_state_to_badge_style(:published), do: "green"
  defp post_state_to_badge_style(:deleted), do: "red"
  defp post_state_to_badge_style(_), do: "default"
end
