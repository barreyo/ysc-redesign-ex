defmodule Ysc.Repo.Migrations.AddPaymentMethod do
  use Ecto.Migration

  def change do
    create table(:payment_methods, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :provider, :string, null: false
      add :provider_id, :string, null: false
      add :provider_customer_id, :string, null: false

      add :type, :string, null: false
      add :provider_type, :string, null: false

      add :last_four, :string, null: true
      add :display_brand, :string, null: true

      add :exp_month, :integer, null: true
      add :exp_year, :integer, null: true

      add :account_type, :string, null: true
      add :routing_number, :string, null: true
      add :bank_name, :string, null: true

      add :user_id, references(:users, column: :id, type: :binary_id), null: false

      add :payload, :map, null: false, default: %{}

      timestamps()
    end

    create unique_index(:payment_methods, [:provider, :provider_id])

    create index(:payment_methods, [:user_id])
    create index(:payment_methods, [:provider_customer_id])

    alter table(:users) do
      add :default_membership_payment_method,
          references(:payment_methods, column: :id, type: :binary_id),
          null: true
    end
  end
end
