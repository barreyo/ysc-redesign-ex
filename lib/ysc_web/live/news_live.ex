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

      <div :if={@featured != nil} class="max-w-screen-xl mx-auto px-4">
        <div
          id="featured"
          class="w-full flex flex-col mb-2 md:mb-48 pb-2 md:pb-48 relative overflow-visible"
        >
          <.link
            navigate={~p"/posts/#{@featured.url_name}"}
            class="w-full hover:opacity-80 transition duration-200 transition-opacity ease-in-out"
          >
            <div class="relative max-h-[112rem]">
              <canvas
                id={"blur-hash-image-#{@featured.id}"}
                src={get_blur_hash(@featured.featured_image)}
                class="absolute left-0 top-0 rounded-lg w-full h-full max-h-[112rem] object-center"
                phx-hook="BlurHashCanvas"
              >
              </canvas>

              <img
                src={featured_image_url(@featured.featured_image)}
                id={"image-#{@featured.id}"}
                loading="lazy"
                phx-hook="BlurHashImage"
                class="object-cover rounded-lg w-full object-center h-full max-h-[112rem]"
              />
            </div>
          </.link>

          <%!-- <div class="w-full bg-gradient-to-t opacity-50 from-white to-zinc-900 h-80 absolute bottom-0">
          </div> --%>

          <div class="py-4 md:py-6 px-2 md:px-8 max-w-screen-lg mx-auto flex flex-col justify-between w-full md:absolute md:bottom-0 md:left-0 md:right-0 md:translate-y-44 z-10 bg-white rounded-lg">
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
          phx-update="stream"
          phx-viewport-top={@page > 1 && "prev-page"}
          phx-viewport-bottom={!@end_of_timeline? && "next-page"}
          phx-page-loading
        >
          <div :for={{id, post} <- @streams.posts} id={id} class="article-preview">
            <.link
              navigate={~p"/posts/#{post.url_name}"}
              class="w-full hover:opacity-80 transition duration-200 transition-opacity ease-in-out"
            >
              <div class="relative">
                <canvas
                  id={"blur-hash-image-#{post.id}"}
                  src={get_blur_hash(post.featured_image)}
                  class="absolute left-0 top-0 rounded-lg w-full h-full object-center aspect-video"
                  phx-hook="BlurHashCanvas"
                >
                </canvas>

                <img
                  src={featured_image_url(post.featured_image)}
                  id={"image-#{post.id}"}
                  loading="lazy"
                  phx-hook="BlurHashImage"
                  class="object-cover rounded-lg w-full object-center aspect-video"
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
    posts = Posts.list_posts((new_page - 1) * per_page, per_page)

    {posts, at, limit} =
      if new_page >= cur_page do
        {posts, -1, per_page * 3 * -1}
      else
        {Enum.reverse(posts), 0, per_page * 3}
      end

    case posts do
      [] ->
        assign(socket, end_of_timeline?: at == -1)

      [_ | _] = posts ->
        socket
        |> assign(end_of_timeline?: false)
        |> assign(:page, new_page)
        |> stream(:posts, posts, at: at, limit: limit)
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
