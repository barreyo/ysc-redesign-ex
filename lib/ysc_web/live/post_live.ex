defmodule YscWeb.PostLive do
  use YscWeb, :live_view

  alias HtmlSanitizeEx.Scrubber

  alias Ysc.Posts
  alias Ysc.Posts.Post

  def render(assigns) do
    ~H"""
    <div class="py-6 lg:py-10">
      <div :if={@post == nil} class="my-14 mx-auto">
        <.empty_viking_state
          viking={4}
          title="Sorry! The article could not be located"
          suggestion="Please check the link you came from and try again."
        />
      </div>

      <div :if={@post != nil} class="max-w-screen-lg mx-auto px-4">
        <div class="max-w-xl mx-auto lg:mx-0">
          <div class="text-sm leading-6 text-zinc-500">
            <p class="sr-only">Date</p>
            <p>
              <%= Timex.format!(post_date(@post), "{WDfull}, {Mfull} {D}, {YYYY}") %>
            </p>
          </div>

          <div class="not-prose pb-4">
            <h1 class="font-extrabold text-zinc-800 text-4xl"><%= @post.title %></h1>
          </div>

          <div id="post-author">
            <.user_card
              email={@post.author.email}
              title="YSC President"
              user_id={@post.author.id}
              most_connected_country={@post.author.most_connected_country}
              first_name={@post.author.first_name}
              last_name={@post.author.last_name}
            />
          </div>
        </div>
      </div>

      <div :if={@post != nil && @post.image_id != nil} id="post-featured-image" class="w-full py-8">
        <img
          src="https://ysc.org/wp-content/uploads/2018/12/2.jpg"
          loading="lazy"
          class="object-cover w-full"
        />
      </div>

      <div :if={@post != nil} class="max-w-screen-lg mx-auto px-4">
        <article class="prose prose-zinc prose-base prose-a:text-blue-600 max-w-xl">
          <div id="article-body" class="py-8">
            <%= raw(post_body(@post)) %>
          </div>
        </article>
      </div>
    </div>
    """
  end

  def mount(%{"id" => id} = _params, _session, socket) do
    post =
      case Ecto.ULID.cast(id) do
        {:ok, ulid_id} -> Posts.get_post(ulid_id, [:author, :featured_image])
        :error -> Posts.get_post_by_url_name(id, [:author, :featured_image])
      end

    {:ok, socket |> assign(:post_id, id) |> assign(:post, post)}
  end

  defp post_date(%Post{published_on: nil} = post), do: post.inserted_at
  defp post_date(%Post{} = post), do: post.published_on

  defp post_body(%Post{rendered_body: nil} = post) do
    Scrubber.scrub(post.raw_body, Scrubber.BasicHTML)
  end

  defp post_body(%Post{} = post) do
    post.rendered_body
  end
end
