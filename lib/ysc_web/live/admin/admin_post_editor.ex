defmodule YscWeb.AdminPostEditorLive do
  use YscWeb, :live_view

  alias Ysc.Posts.Post
  alias Ysc.Posts

  @save_debounce_timeout 2000

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
      <.simple_form for={@form} id="edit_post_form" phx-submit="save" phx-change="post-update">
        <div class="w-full flex flex-row items-center align-middle">
          <.input type="text-growing" field={@form[:title]} phx-debounce="500" />

          <p class={"text-sm text-zinc-600 transition duration-200 ease-in-out align-middle inline-block items-center ml-4 px-4 mt-4 #{if @saving? == true, do: "opacity-100", else: "opacity-0"}"}>
            <span>
              <.icon name="hero-arrow-path" class="w-4 h-4 -mt-0.5 animate-spin mr-1" />
            </span>
            Saving...
          </p>
        </div>

        <div class="prose prose-zinc prose-base prose-a:text-blue-600 max-w-none mx-auto">
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
      </.simple_form>
    </.side_menu>
    """
  end

  def mount(%{"id" => id} = params, _session, socket) do
    post = Posts.get_post!(id)
    update_post_changeset = Post.update_post_changeset(post, %{})

    YscWeb.Endpoint.subscribe("post_saved:#{id}")

    {:ok,
     socket
     |> assign(:page_title, "Posts")
     |> assign(:active_page, :news)
     |> assign(:saving?, false)
     |> assign(:post_id, post.id)
     |> assign(form: to_form(update_post_changeset, as: "post"))}
  end

  def handle_event("post-update", %{"post" => values}, socket) do
    Debouncer.apply(
      socket.assigns[:post_id],
      fn ->
        Posts.update_post(
          %Post{id: socket.assigns[:post_id]},
          values,
          socket.assigns[:current_user]
        )

        YscWeb.Endpoint.broadcast(
          "post_saved:#{socket.assigns[:post_id]}",
          "saved",
          socket.assigns[:post_id]
        )
      end,
      @save_debounce_timeout
    )

    {:noreply, socket |> assign(:saving?, true)}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "saved"}, socket) do
    {:noreply, assign(socket, :saving?, false)}
  end
end
