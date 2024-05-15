defmodule YscWeb.PostLive do
  use YscWeb, :live_view

  alias HtmlSanitizeEx.Scrubber

  alias Ysc.Posts
  alias Ysc.Posts.Post
  alias Ysc.Posts.Comment

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

      <div :if={@post != nil && @post.image_id != nil} id="post-featured-image" class="w-full py-8">
        <img
          src="https://ysc.org/wp-content/uploads/2018/12/2.jpg"
          loading="lazy"
          class="object-cover w-full"
        />
      </div>

      <div :if={@post != nil} class="max-w-screen-lg mx-auto px-4">
        <article class="prose prose-zinc prose-base prose-a:text-blue-600 max-w-xl mx-auto lg:mx-0">
          <div id="article-body" class="py-8 post-render">
            <%= raw(@post.raw_body) %>
          </div>
        </article>
      </div>

      <div :if={@post != nil && @current_user != nil} class="max-w-screen-lg mx-auto px-4">
        <section class="max-w-xl mx-auto lg:mx-0 py-8">
          <div class="max-w-2xl">
            <div class="flex justify-between items-center mb-6">
              <h2 class="text-2xl font-bold text-zinc-900 leading-8">
                Discussion (<%= @post.comment_count %>)
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
                class="inline-flex items-center py-2.5 px-4 text-sm font-bold text-center text-zinc-100 bg-blue-700 rounded focus:ring-4 focus:ring-blue-200 hover:bg-blue-800 mt-4"
              >
                Post Comment
              </button>
            </.form>

            <div id="comment-section" phx-update="stream">
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

    {:ok,
     socket
     |> assign(:post_id, id)
     |> assign(:post, post)
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

    # TODO: No redirect
    {:noreply, socket |> redirect(to: ~p"/posts/#{socket.assigns[:post].url_name}")}
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
end
