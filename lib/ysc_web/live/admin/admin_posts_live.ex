defmodule YscWeb.AdminPostsLive do
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
      <div class="flex justify-between py-6">
        <h1 class="text-2xl font-semibold leading-8 text-zinc-800">
          Posts
        </h1>

        <.button>
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
                    type: "select",
                    multiple: false,
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
            <p class="text-sm font-semibold"><%= post.title %></p>
          </:col>

          <:col :let={{_, post}} label="Author" field={:author_name}>
            <%= "#{String.capitalize(String.downcase(post.author.first_name))} #{String.capitalize(String.downcase(post.author.last_name))}" %>
          </:col>

          <:col :let={{_, post}} label="State" field={:state}>
            <.badge type={post_state_to_badge_style(post.state)}>
              <%= "#{post.state}" %>
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
    {:ok,
     socket
     |> assign(:page_title, "Posts")
     |> assign(:active_page, :news)}
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

  defp maybe_update_filter(%{"value" => [""]} = filter), do: Map.replace(filter, "value", "")
  defp maybe_update_filter(filter), do: filter

  defp post_state_to_badge_style(:draft), do: "yellow"
  defp post_state_to_badge_style(:published), do: "green"
  defp post_state_to_badge_style(:deleted), do: "dark"
  defp post_state_to_badge_style(_), do: "default"
end
