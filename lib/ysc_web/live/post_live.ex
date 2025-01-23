defmodule YscWeb.PostLive do
  alias Ysc.Media.Image
  use YscWeb, :live_view

  alias HtmlSanitizeEx.Scrubber

  alias Ysc.Posts
  alias Ysc.Posts.Post
  alias Ysc.Posts.Comment

  def render(assigns) do
    ~H"""
    <div class="py-8 lg:py-10">
      <div :if={@post == nil} class="my-14 mx-auto">
        <.empty_viking_state
          viking={4}
          title="Sorry! The article could not be located"
          suggestion="Please check the link you came from and try again."
        />
      </div>

      <div :if={@post != nil} class="max-w-screen-lg mx-auto px-4">
        <div class="max-w-xl mx-auto">
          <div class="text-sm leading-6 text-zinc-600">
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
              title={@post.author.board_position}
              user_id={@post.author.id}
              most_connected_country={@post.author.most_connected_country}
              first_name={@post.author.first_name}
              last_name={@post.author.last_name}
            />
          </div>
        </div>
      </div>

      <div
        :if={@post != nil && @post.image_id != nil}
        id="post-featured-image"
        class="mt-8 relative mx-auto rounded max-w-5xl"
      >
        <canvas
          id={"blur-hash-image-#{@post.image_id}"}
          src={get_blur_hash(@post.featured_image)}
          class="absolute m-auto left-0 right-0 w-full h-full z-0 rounded"
          phx-hook="BlurHashCanvas"
        >
        </canvas>

        <img
          src={featured_image_url(@post.featured_image)}
          id={"image-#{@post.image_id}"}
          loading="lazy"
          class="object-cover h-full mx-auto z-[1] rounded"
          phx-hook="BlurHashImage"
        />
      </div>

      <div :if={@post != nil} class="max-w-screen-lg mx-auto px-4">
        <article class="prose prose-zinc prose-base prose-a:text-blue-600 max-w-xl mx-auto">
          <div id="article-body" class="py-8 post-render">
            <%= raw(@post.raw_body) %>
          </div>
        </article>
      </div>

      <div :if={@post != nil && @current_user != nil} class="max-w-screen-lg mx-auto px-4">
        <section class="max-w-xl mx-auto py-8">
          <div class="max-w-2xl">
            <div class="flex justify-between items-center mb-6">
              <h2 class="text-2xl font-bold text-zinc-900 leading-8">
                Discussion (<%= @n_comments %>)
              </h2>
            </div>

            <.form class="mb-6" for={@form} id="primary-post-comment" phx-submit="save">
              <.input
                field={@form[:text]}
                type="textarea"
                id="comment"
                rows="4"
                class="px-0 w-full text-sm text-zinc-900 border-0 focus:ring-0 focus:outline-none"
                placeholder="Write a nice comment..."
                required
              >
              </.input>
              <input type="hidden" name="comment[post_id]" value={@post.id} />
              <button
                type="submit"
                class={[
                  "inline-flex items-center py-2.5 px-4 text-sm font-bold text-center text-zinc-100 bg-blue-700 rounded focus:ring-4 focus:ring-blue-200 hover:bg-blue-800 mt-4 disabled:opacity-80 disabled:cursor-not-allowed",
                  @loading && "disabled"
                ]}
                disabled={@loading}
              >
                Post Comment
                <.icon
                  :if={@loading}
                  name="hero-arrow-path"
                  class="w-5 h-5 animate-spin ml-2 text-zinc-100"
                />
              </button>
            </.form>

            <div id={"comment-section-#{@post.id}"} phx-update="stream">
              <.comment
                :for={{id, comment} <- @streams.comments}
                id={id}
                text={comment.text}
                author={"#{String.capitalize(comment.author.first_name)} #{String.capitalize(comment.author.last_name)}"}
                author_email={comment.author.email}
                author_most_connected={comment.author.most_connected_country}
                author_id={comment.author.id}
                date={comment.inserted_at}
                form={@form}
                post_id={@post.id}
                reply_to_comment_id={get_reply_to_id(comment)}
                reply={comment_is_reply(comment)}
                animate={@animate_insert}
              />
            </div>
          </div>
        </section>
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

    new_comment_changeset = Posts.Comment.new_comment_changeset(%Posts.Comment{}, %{})
    comments = Posts.get_comments_for_post(post.id, [:author])
    sorted_comments = Posts.sort_comments_for_render(comments)

    YscWeb.Endpoint.subscribe(Posts.post_topic(post.id))

    {:ok,
     socket
     |> assign(:post_id, id)
     |> assign(:post, post)
     |> assign(:page_title, post.title)
     |> assign(:animate_insert, false)
     |> assign(:n_comments, post.comment_count)
     |> assign(:loading, false)
     |> assign_form(new_comment_changeset)
     |> stream(:comments, sorted_comments), temporary_assigns: [form: nil]}
  end

  def handle_event("save", %{"comment" => comment}, socket) do
    text_body = Map.get(comment, "text", "")
    # Ensure no bad stuff gets rendered ever
    # It will be escaped later for safety but lets be defensive
    scrubbed_comment = Map.put(comment, "text", Scrubber.scrub(text_body, Scrubber.BasicHTML))
    current_user = socket.assigns[:current_user]

    Posts.add_comment_to_post(scrubbed_comment, current_user)

    {:noreply, socket |> assign(:loading, true)}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "new_comment", payload: new_comment}, socket) do
    loaded = Posts.get_comment!(new_comment.id, [:author])
    new_comment_changeset = Posts.Comment.new_comment_changeset(%Posts.Comment{}, %{})

    new_socket =
      socket
      |> assign(:animate_insert, true)
      |> stream_insert(:comments, loaded, at: Posts.get_insert_index_for_comment(new_comment))
      |> assign(:n_comments, socket.assigns[:n_comments] + 1)

    if new_comment.user_id == socket.assigns[:current_user].id do
      {:noreply,
       new_socket
       |> put_flash(:info, "Your comment has been posted!")
       |> assign(:loading, false)
       |> assign_form(new_comment_changeset)}
    else
      {:noreply, new_socket}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "comment")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end

  defp post_date(%Post{published_on: nil} = post), do: post.inserted_at
  defp post_date(%Post{} = post), do: post.published_on

  defp post_body(%Post{rendered_body: nil} = post) do
    Scrubber.scrub(post.raw_body, Scrubber.BasicHTML)
  end

  defp post_body(%Post{} = post) do
    post.rendered_body
  end

  defp comment_is_reply(%Comment{comment_id: nil}), do: false
  defp comment_is_reply(%Comment{}), do: true

  defp get_reply_to_id(%Comment{comment_id: nil} = comment), do: comment.id
  defp get_reply_to_id(comment), do: comment.comment_id

  defp featured_image_url(%Image{optimized_image_path: nil} = image), do: image.raw_image_path
  defp featured_image_url(%Image{optimized_image_path: optimized_path}), do: optimized_path

  defp get_blur_hash(%Image{blur_hash: nil}), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  defp get_blur_hash(%Image{blur_hash: blur_hash}), do: blur_hash
end
