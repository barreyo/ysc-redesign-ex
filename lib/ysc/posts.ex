defmodule Ysc.Posts do
  @moduledoc """
  The Posts context.
  """

  import Ecto.Query, warn: false

  alias Ysc.Posts.Post
  alias Ysc.Repo
  alias YscWeb.Authorization.Policy
  alias Ysc.Accounts.User

  def get_post!(id) do
    Repo.get!(Post, id)
  end

  def get_post_by_url_name!(url_name) do
    Repo.get_by!(Post, url_name: url_name)
  end

  def list_posts_paginated(params) do
    Post
    |> join(:left, [p], u in assoc(p, :author), as: :author)
    |> preload([author: p], author: p)
    |> Flop.validate_and_run(params, for: Post)
  end

  def update_post(post, params, %User{} = current_user) do
    with :ok <- Policy.authorize(:posts_update, current_user, post) do
      post |> Post.update_post_changeset(params) |> Repo.update()
    end
  end

  def get_all_authors() do
    from(
      post in Post,
      left_join: user in assoc(post, :author),
      distinct: post.user_id,
      select: %{
        "user_id" => post.user_id,
        "author_first" => user.first_name,
        "author_last" => user.last_name
      },
      order_by: [user.first_name]
    )
    |> Repo.all()
    |> format_authors()
  end

  defp format_authors(result) do
    result
    |> Enum.reduce([], fn entry, acc ->
      [{name_format(entry), entry["user_id"]}]
    end)
  end

  defp name_format(%{"author_first" => first, "author_last" => last}) do
    "#{String.capitalize(String.downcase(first))} #{String.downcase(String.capitalize(last))}"
  end
end
