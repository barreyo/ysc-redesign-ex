defmodule Ysc.Articles.NewsArticle do
  use Ecto.Schema
  # import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "article" do
    belongs_to :author, Ysc.Accounts.User, foreign_key: :user_id, references: :id

    field :featured_post, :boolean
  end
end
