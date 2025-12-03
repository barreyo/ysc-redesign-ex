defmodule YscWeb.NewsLive do
  use YscWeb, :live_view

  alias HtmlSanitizeEx.Scrubber

  alias Ysc.Posts
  alias Ysc.Posts.Post
  alias Ysc.Media.Image

  def render(assigns) do
    ~H"""
    <div class="py-6 md:py-10">
      <div class="max-w-screen-lg mx-auto px-4">
        <div class="prose prose-zinc pb-8">
          <h1>Club News</h1>
        </div>
      </div>

      <div :if={@featured != nil} class="max-w-screen-lg mx-auto px-4">
        <div id="featured" class="w-full flex flex-col pb-2">
          <.link
            navigate={~p"/posts/#{@featured.url_name}"}
            class="w-full hover:opacity-80 transition-opacity duration-200 ease-in-out"
          >
            <div class="relative w-full aspect-video">
              <canvas
                id={"blur-hash-image-#{@featured.id}"}
                src={get_blur_hash(@featured.featured_image)}
                class="absolute inset-0 z-0 rounded-lg w-full h-full object-cover"
                phx-hook="BlurHashCanvas"
              >
              </canvas>
              <img
                src={featured_image_url(@featured.featured_image)}
                id={"image-#{@featured.id}"}
                phx-hook="BlurHashImage"
                class="absolute inset-0 z-[1] opacity-0 transition-opacity duration-300 ease-out object-cover rounded-lg w-full h-full"
                loading="eager"
                alt={
                  if @featured.featured_image,
                    do:
                      @featured.featured_image.alt_text || @featured.featured_image.title ||
                        @featured.title || "Featured news image",
                    else: "Featured news image"
                }
              />
            </div>
          </.link>

          <%!-- <div class="w-full bg-gradient-to-t opacity-50 from-white to-zinc-900 h-80 absolute bottom-0">
          </div> --%>

          <div class="py-4 md:py-6 px-2 lg:px-4 max-w-screen-lg mx-auto flex flex-col justify-between w-full">
            <div>
              <div class="flex items-center gap-1 mb-2">
                <.badge type="yellow">
                  <.icon name="hero-star-solid" class="w-4 h-4 text-yellow-500 me-1 -mt-1" />Pinned News
                </.badge>
              </div>

              <div class="text-sm leading-6 text-zinc-600">
                <p class="sr-only">Date</p>
                <p>
                  <%= Timex.format!(@featured.published_on, "{WDfull}, {Mfull} {D}, {YYYY}") %>
                </p>
              </div>

              <.link
                navigate={~p"/posts/#{@featured.url_name}"}
                class="font-extrabold text-zinc-800 text-4xl md:text-5xl leading-tight drop-shadow-sm"
              >
                <%= @featured.title %>
              </.link>

              <article class="mx-auto max-w-none text-zinc-600 mt-3 md:mt-4 prose prose-invert prose-zinc prose-base md:prose-lg prose-a:text-blue-300 max-h-40 text-wrap overflow-hidden">
                <%= raw(preview_text(@featured)) %>
              </article>
            </div>

            <div class="pt-6">
              <.user_card
                email={@featured.author.email}
                title={@featured.author.board_position}
                user_id={@featured.author.id}
                most_connected_country={@featured.author.most_connected_country}
                first_name={@featured.author.first_name}
                last_name={@featured.author.last_name}
              />
            </div>
          </div>
        </div>
      </div>

      <div class="max-w-screen-lg mx-auto px-4">
        <div
          :if={@post_count > 0}
          id="news-grid"
          class="grid grid-cols-1 md:grid-cols-2 py-4 gap-8"
          phx-viewport-top={@page > 1 && "prev-page"}
          phx-viewport-bottom={!@end_of_timeline? && "next-page"}
          phx-page-loading
        >
          <div :for={post <- @posts} id={"post-#{post.id}"} class="article-preview">
            <.link
              navigate={~p"/posts/#{post.url_name}"}
              class="w-full hover:opacity-80 transition duration-200 transition-opacity ease-in-out"
            >
              <div class="relative aspect-video">
                <canvas
                  id={"blur-hash-image-#{post.id}"}
                  src={get_blur_hash(post.featured_image)}
                  class="absolute inset-0 z-0 rounded-lg w-full h-full object-cover"
                  phx-hook="BlurHashCanvas"
                >
                </canvas>

                <img
                  src={featured_image_url(post.featured_image)}
                  id={"image-#{post.id}"}
                  loading="lazy"
                  phx-hook="BlurHashImage"
                  class="absolute inset-0 z-[1] opacity-0 transition-opacity duration-300 ease-out rounded-lg w-full h-full object-cover"
                  alt={
                    if post.featured_image,
                      do:
                        post.featured_image.alt_text || post.featured_image.title || post.title ||
                          "News article image",
                      else: "News article image"
                  }
                />
              </div>
            </.link>

            <div class="px-2 flex flex-col justify-between w-full py-4">
              <div>
                <div class="text-sm leading-6 text-zinc-600">
                  <p class="sr-only">Date</p>
                  <p>
                    <%= Timex.format!(post.published_on, "{WDfull}, {Mfull} {D}, {YYYY}") %>
                  </p>
                </div>

                <.link
                  navigate={~p"/posts/#{post.url_name}"}
                  class="font-extrabold text-zinc-800 text-3xl leading-10"
                >
                  <%= post.title %>
                </.link>

                <article class="text-zinc-600 mt-4 prose prose-zinc prose-base prose-a:text-blue-600 max-h-[10.5rem] overflow-hidden text-wrap">
                  <%= raw(preview_text(post)) %>
                </article>
              </div>

              <div class="pt-6">
                <.user_card
                  email={post.author.email}
                  title={post.author.board_position}
                  user_id={post.author.id}
                  most_connected_country={post.author.most_connected_country}
                  first_name={post.author.first_name}
                  last_name={post.author.last_name}
                />
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    featured_post = Posts.get_featured_post() |> Ysc.Repo.preload([:author, :featured_image])
    post_count = Posts.count_published_posts()

    {:ok,
     socket
     |> assign(:post_count, post_count)
     |> assign(:page_title, "News")
     |> assign(:featured, featured_post)
     |> assign(:posts, [])
     |> assign(page: 1, per_page: 10)
     |> paginate_posts(1)}
  end

  def handle_event("next-page", _, socket) do
    {:noreply, paginate_posts(socket, socket.assigns.page + 1)}
  end

  def handle_event("prev-page", %{"_overran" => true}, socket) do
    {:noreply, paginate_posts(socket, 1)}
  end

  def handle_event("prev-page", _, socket) do
    if socket.assigns.page > 1 do
      {:noreply, paginate_posts(socket, socket.assigns.page - 1)}
    else
      {:noreply, socket}
    end
  end

  defp paginate_posts(socket, new_page) when new_page >= 1 do
    %{per_page: per_page, page: cur_page} = socket.assigns

    # Posts.list_posts already preloads :author and :featured_image
    # Ecto will batch load these associations automatically
    new_posts = Posts.list_posts((new_page - 1) * per_page, per_page)

    case new_posts do
      [] ->
        socket
        |> assign(:end_of_timeline?, new_page >= cur_page)
        |> assign(:page, new_page)

      [_ | _] = new_posts ->
        # Get existing posts
        existing_posts = Map.get(socket.assigns, :posts, [])

        # Combine posts, avoiding duplicates by ID
        all_posts = existing_posts ++ new_posts
        unique_posts = Enum.uniq_by(all_posts, & &1.id)

        # Sort by published_on descending to maintain chronological order
        sorted_posts = Enum.sort_by(unique_posts, & &1.published_on, {:desc, DateTime})

        socket
        |> assign(:end_of_timeline?, length(new_posts) < per_page)
        |> assign(:page, new_page)
        |> assign(:posts, sorted_posts)
    end
  end

  # Do some magic to try and figure out what the preview text should be
  defp preview_text(%Post{preview_text: nil} = post) do
    Scrubber.scrub(post.raw_body, YscWeb.Scrubber.StripEverythingExceptText)
  end

  defp preview_text(post), do: post.preview_text

  defp get_blur_hash(nil), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  defp get_blur_hash(%Image{blur_hash: nil}), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  defp get_blur_hash(%Image{blur_hash: blur_hash}), do: blur_hash

  defp featured_image_url(nil), do: "/images/ysc_logo.png"
  defp featured_image_url(%Image{optimized_image_path: nil} = image), do: image.raw_image_path
  defp featured_image_url(%Image{optimized_image_path: optimized_path}), do: optimized_path
end
