defmodule Ysc.Repo.Migrations.AddPostsComments do
  use Ecto.Migration

  def change do
    create table(:posts, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      # Who posted it
      add :user_id, references(:users, column: :id, type: :binary_id), null: false

      add :state, :string, null: false, default: "draft"
      add :title, :string, default: "Untitled Post"

      add :url_name, :text
      add :rendered_body, :text
      add :raw_body, :text

      # Featured image
      add :image_id, references(:images, column: :id, type: :binary_id)
      add :featured_post, :boolean, default: false

      add :published_on, :utc_datetime
      add :deleted_on, :utc_datetime

      timestamps()
    end

    create unique_index(:posts, [:url_name])

    create table(:post_events, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :user_id, references(:users, column: :id, type: :binary_id), null: false
      add :post_id, references(:posts, column: :id, type: :binary_id), null: false

      add :event_type, :string, null: false

      add :from, :text
      add :to, :text

      timestamps()
    end

    create index(:post_events, [:post_id])

    create table(:comments, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :user_id, references(:users, column: :id, type: :binary_id), null: false
      add :post_id, references(:posts, column: :id, type: :binary_id), null: false

      # If is a reply
      add :comment_id, references(:comments, column: :id, type: :binary_id), null: true

      add :rendered_body, :text
      add :raw_body, :text

      timestamps()
    end

    create index(:comments, [:post_id])
    create index(:comments, [:user_id])
    create index(:comments, [:comment_id])
  end
end
