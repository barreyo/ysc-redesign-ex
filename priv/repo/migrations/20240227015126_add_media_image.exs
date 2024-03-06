defmodule Ysc.Repo.Migrations.AddMediaImage do
  use Ecto.Migration

  def change do
    create table(:images, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :user_id, references(:users, column: :id, type: :binary_id), null: false

      add :title, :string, null: true
      add :alt_text, :string, size: 512, null: true

      add :optimized_image_path, :string, size: 2048, null: true
      add :raw_image_path, :string, size: 2048, null: false
      add :thumbnail_path, :string, size: 2048, null: true
      add :blur_hash, :string, size: 1024, null: true

      add :width, :integer, default: 0
      add :height, :integer, default: 0

      add :processing_state, :string, null: false, default: "unprocessed"

      add :upload_data, :map, default: %{}

      timestamps()
    end

    create index(:images, [:processing_state])
    create index(:images, [:inserted_at])
  end
end
