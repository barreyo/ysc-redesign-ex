defmodule Ysc.Ledgers.AccountTransaction do
  use Ecto.Schema
  import Ecto.Changeset

  schema "account_transactions" do
    field :description, :string

    field :transaction_type, TransactionType
    belongs_to :ledger, Ysc.Ledgers.Ledger
    belongs_to :account, Ysc.Ledgers.LedgerAccount

    field :amount, Money.Ecto.Composite.Type

    timestamps(updated_at: false)
  end

  def insert_account_transaction_changeset(account_transaction, attrs) do
    account_transaction
    |> cast(attrs, [:description, :transaction_type, :amount, :ledger_id, :account_id])
    |> validate_required([
      :transaction_type,
      :ledger_id,
      :account_id,
      :amount,
      :ledger_id,
      :account_id
    ])
    |> validate_number(:amount, greater_than: 0)
  end
end
