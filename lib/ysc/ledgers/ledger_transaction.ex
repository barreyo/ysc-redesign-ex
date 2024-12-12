defmodule Ysc.Ledgers.LedgerTransaction do
  use Ecto.Schema

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "ledger_transactions" do
    field :type, LedgerTransactionType
    belongs_to :payment, Ysc.Ledgers.Payment, foreign_key: :payment_id, references: :id
    field :total_amount, Money.Ecto.Composite.Type, default_currency: :USD
    field :status, LedgerTransactionStatus

    timestamps()
  end
end
