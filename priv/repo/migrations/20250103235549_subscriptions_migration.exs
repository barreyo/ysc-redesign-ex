defmodule Ysc.Repo.Migrations.CreateSubscriptions do
  use Ecto.Migration

  def change do
    create table(:subscriptions, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :name, :string, null: false
      add :ends_at, :utc_datetime
      add :trial_ends_at, :utc_datetime

      add :stripe_id, :string
      add :stripe_status, :string

      add :start_date, :utc_datetime, null: true
      add :current_period_start, :utc_datetime, null: true
      add :current_period_end, :utc_datetime, null: true

      add :user_id, :binary_id, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:subscriptions, [:stripe_id])
    create index(:subscriptions, [:user_id, :stripe_status])

    create table(:subscription_items, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :subscription_id, references(:subscriptions, on_delete: :delete_all, type: :binary_id),
        null: false

      add :stripe_id, :string, null: false
      add :stripe_product_id, :string, null: false
      add :stripe_price_id, :string, null: false
      add :quantity, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:subscription_items, [:stripe_id])
    create index(:subscription_items, [:subscription_id])
  end
end
