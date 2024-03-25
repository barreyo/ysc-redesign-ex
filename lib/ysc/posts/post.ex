defmodule Ysc.Posts.Post do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {
    Flop.Schema,
    filterable: [
      :state,
      :user_id
    ],
    sortable: [:inserted_at, :title, :state, :author_name],
    default_limit: 50,
    max_limit: 200,
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    },
    adapter_opts: [
      join_fields: [
        author_first: [
          binding: :author,
          field: :first_name,
          ecto_type: :string
        ],
        author_last: [
          binding: :author,
          field: :first_name,
          ecto_type: :string
        ]
      ],
      compound_fields: [
        author_name: [:author_first, :author_last]
      ]
    ]
  }

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "posts" do
    belongs_to :author, Ysc.Accounts.User, foreign_key: :user_id, references: :id

    field :state, PostState
    field :title, :string

    field :url_name, :string
    field :rendered_body, :string
    field :raw_body, :string

    belongs_to :featured_image, Ysc.Media.Image, foreign_key: :image_id, references: :id

    field :featured_post, :boolean

    field :published_on, :utc_datetime
    field :deleted_on, :utc_datetime

    timestamps()
  end

  @spec new_post_changeset(
          {map(), map()}
          | %{
              :__struct__ => atom() | %{:__changeset__ => map(), optional(any()) => any()},
              optional(atom()) => any()
            },
          :invalid | %{optional(:__struct__) => none(), optional(atom() | binary()) => any()}
        ) :: Ecto.Changeset.t()
  def new_post_changeset(post, attrs, _opts \\ []) do
    post
    |> cast(attrs, [
      :user_id,
      :state,
      :title,
      :url_name,
      :rendered_body,
      :raw_body,
      :image_id,
      :featured_post,
      :published_on,
      :deleted_on
    ])
    |> validate_length(:title, max: 150)
    |> validate_length(:url_name, min: 1, max: 150)
  end

  def update_post_changeset(post, attrs, _opts \\ []) do
    post
    |> cast(attrs, [
      :state,
      :title,
      :url_name,
      :rendered_body,
      :raw_body,
      :image_id,
      :featured_post,
      :published_on
    ])
    |> validate_length(:title, max: 150)
    |> validate_length(:url_name, min: 1, max: 150)
  end
end
