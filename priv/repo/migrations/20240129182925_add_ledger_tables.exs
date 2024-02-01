defmodule Ysc.Repo.Migrations.AddLedgerTables do
  use Ecto.Migration

  def change do
    create table(:ledgers) do
      add :name, :string, null: false
      add :description, :string, null: true
      add :ledger_type, :string, null: false

      timestamps()
    end

    create unique_index(:ledgers, [:name])

    create table(:ledger_accounts) do
      add :account_type, :string, null: false
      add :name, :string, null: false
      add :description, :string, null: true

      add :user_id,
          references(
            :users,
            on_delete: :restrict,
            column: :id,
            type: :binary_id
          ),
          null: true

      timestamps()
    end

    create index(:ledger_accounts, [:user_id])
    create unique_index(:ledger_accounts, [:name])

    create table(:account_transactions) do
      add :description, :string, null: false

      add :transaction_type, :string, null: false
      add :ledger_id, references(:ledgers, on_delete: :restrict), null: false
      add :account_id, references(:ledger_accounts, on_delete: :restrict), null: false

      add :amount, :integer, null: false

      # Immutable
      timestamps(updated_at: false)
    end

    create index(:account_transactions, [:ledger_id])
    create index(:account_transactions, [:account_id])
  end
end
