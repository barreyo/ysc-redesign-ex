defmodule Ysc.Repo.Migrations.AddWebhookModel do
  use Ecto.Migration

  def change do
    create table(:webhook_events, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :provider, :string, null: false
      add :state, :string, default: "pending"
      add :event_id, :string, null: false
      add :event_type, :string, null: false

      add :payload, :map, null: false, default: %{}

      timestamps()
    end

    create unique_index(:webhook_events, [:provider, :event_id])
    create index(:webhook_events, [:state])
  end
end
