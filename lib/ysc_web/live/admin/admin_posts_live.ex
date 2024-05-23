defmodule YscWeb.AdminPostsLive do
  alias Ysc.Posts.Post
  use YscWeb, :live_view

  alias Ysc.Posts

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
        :if={@live_action == :new}
        id="new-post-modal"
        on_cancel={JS.navigate(~p"/admin/posts")}
        show
      >
        <.header>
          Add new post
        </.header>
        <.simple_form for={@form} phx-change="validate" phx-submit="save">
          <.input type="text" field={@form[:title]} label="Title" />

          <div class="flex flex-row justify-end w-full pt-8">
            <button
              phx-click={JS.navigate(~p"/admin/posts")}
              class="rounded hover:bg-zinc-100 py-2 px-3 mr-4 transition duration-200 ease-in-out text-sm font-semibold leading-6 text-zinc-600"
            >
              Cancel
            </button>
            <.button type="submit">Create Post</.button>
          </div>
        </.simple_form>
      </.modal>

      <div class="flex justify-between py-6">
        <h1 class="text-2xl font-semibold leading-8 text-zinc-800">
          Posts
        </h1>

        <.button phx-click={JS.navigate(~p"/admin/posts/new")}>
          <.icon name="hero-document-plus" class="w-5 h-5 -mt-1" /><span class="ms-1">New Post</span>
        </.button>
      </div>

      <div class="w-full pt-4">
        <div id="admin-user-filters" class="pb-4 flex">
          <.dropdown id="filter-posts-dropdown" class="group hover:bg-zinc-100">
            <:button_block>
              <.icon
                name="hero-funnel"
                class="mr-1 text-zinc-600 w-5 h-5 group-hover:text-zinc-800 -mt-0.5"
              /> Filters
            </:button_block>

            <div class="w-full px-4 py-3">
              <.filter_form
                fields={[
                  state: [
                    label: "State",
                    type: "checkgroup",
                    multiple: true,
                    op: :in,
                    options: [
                      {"Published", :published},
                      {"Draft", :draft},
                      {"Deleted", :deleted}
                    ]
                  ],
                  user_id: [
                    label: "Author",
                    type: "checkgroup",
                    multiple: true,
                    op: :in,
                    options: @author_filter
                  ]
                ]}
                meta={@meta}
                id="posts-filter-form"
              />
            </div>

            <div class="px-4 py-4">
              <button
                class="rounded hover:bg-zinc-100 py-2 px-3 transition duration-200 ease-in-out text-sm font-semibold leading-6 text-zinc-800 active:text-zinc-100/80 w-full"
                phx-click={JS.navigate(~p"/admin/posts")}
              >
                <.icon name="hero-x-circle" class="w-5 h-5 -mt-1" /> Clear filters
              </button>
            </div>
          </.dropdown>
        </div>

        <Flop.Phoenix.table
          id="admin_posts_list"
          items={@streams.posts}
          meta={@meta}
          path={~p"/admin/posts"}
        >
          <:col :let={{_, post}} label="Title" field={:title}>
            <p class="text-sm font-semibold">
              <%= post.title %>
              <span
                :if={post.comment_count > 0}
                class="relative text-zinc-600 ml-2 rounded px-2 py-1 text-sm"
              >
                <.icon name="hero-chat-bubble-oval-left" class="w-4 h-4 -mt-0.5" />
                <%= post.comment_count %>
              </span>
            </p>
          </:col>

          <:col :let={{_, post}} label="Author" field={:author_name}>
            <%= "#{String.capitalize(post.author.first_name)} #{String.capitalize(post.author.last_name)}" %>
          </:col>

          <:col :let={{_, post}} label="State" field={:state}>
            <.badge type={post_state_to_badge_style(post.state)}>
              <%= String.capitalize("#{post.state}") %>
            </.badge>
          </:col>

          <:action :let={{_, post}} label="Action">
            <button
              phx-click={JS.navigate(~p"/admin/posts/#{post.id}")}
              class="text-blue-600 font-semibold hover:underline cursor-pointer"
            >
              Edit
            </button>
          </:action>
        </Flop.Phoenix.table>
      </div>
    </.side_menu>
    """
  end

  @spec mount(any(), any(), map()) :: {:ok, map()}
  def mount(_params, _session, socket) do
    new_post_changeset = Post.new_post_changeset(%Post{}, %{})

    {:ok,
     socket
     |> assign(:page_title, "Posts")
     |> assign(:active_page, :news)
     |> assign(form: to_form(new_post_changeset, as: "new_post")),
     temporary_assigns: [author_filter: []]}
  end

  def handle_params(params, _uri, socket) do
    case Posts.list_posts_paginated(params) do
      {:ok, {posts, meta}} ->
        author_filter = Ysc.Posts.get_all_authors()

        {:noreply,
         assign(socket, meta: meta)
         |> assign(author_filter: author_filter)
         |> stream(:posts, posts, reset: true)}

      {:error, _meta} ->
        {:noreply, push_navigate(socket, to: ~p"/admin/posts")}
    end
  end

  def handle_event("update-filter", params, socket) do
    params = Map.delete(params, "_target")

    updated_filters =
      Enum.reduce(params["filters"], %{}, fn {k, v}, red ->
        Map.put(red, k, maybe_update_filter(v))
      end)

    new_params = Map.replace(params, "filters", updated_filters)

    {:noreply, push_patch(socket, to: ~p"/admin/posts?#{new_params}")}
  end

  def handle_event("validate", %{"new_post" => params}, socket) do
    changeset = Post.new_post_changeset(%Post{}, params)
    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"new_post" => params}, socket) do
    updated_params = Map.put(params, "url_name", title_to_url_name(params["title"]))
    result = Posts.create_post(updated_params, socket.assigns[:current_user])

    case result do
      {:ok, new_post} -> {:noreply, socket |> redirect(to: ~p"/admin/posts/#{new_post.id}")}
      _ -> {:noreply, socket |> put_flash(:error, "Something went wrong try again.")}
    end
  end

  def handle_event("new-post", _params, socket) do
    url_name = title_to_url_name("")
    result = Posts.create_post(%{"url_name" => url_name}, socket.assigns[:current_user])

    case result do
      {:ok, new_post} -> {:noreply, socket |> redirect(to: ~p"/admin/posts/#{new_post.id}")}
      _ -> {:noreply, socket |> put_flash(:error, "Something went wrong try again.")}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "new_post")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end

  defp maybe_replace_url_name(""), do: "new-untitled-post"
  defp maybe_replace_url_name(value), do: value

  defp title_to_url_name(title) do
    dd = String.downcase(Regex.replace(~r/\s+/u, title, "-"))
    stripped_punctuation = Regex.replace(~r/[^0-9\-a-z]/u, dd, "")

    maybe_add_number_to_url_name(maybe_replace_url_name(stripped_punctuation))
  end

  defp maybe_add_number_to_url_name(url_name) do
    case Posts.count_posts_with_url_name(url_name) do
      0 -> url_name
      n -> "#{url_name}-#{n + 1}"
    end
  end

  defp maybe_update_filter(%{"value" => [""]} = filter), do: Map.replace(filter, "value", "")
  defp maybe_update_filter(filter), do: filter

  defp post_state_to_badge_style(:draft), do: "yellow"
  defp post_state_to_badge_style(:published), do: "green"
  defp post_state_to_badge_style(:deleted), do: "red"
  defp post_state_to_badge_style(_), do: "default"
end
