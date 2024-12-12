defmodule Ysc.Ledgers.LedgerEntry do
  use Ecto.Schema

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "ledger_entries" do
    belongs_to :account, Ysc.Ledgers.LedgerAccounts,
      foreign_key: :account_id,
      references: :id

    field :related_entity_type, LedgerEntryEntityType
    field :related_entity_id, Ecto.ULID

    belongs_to :payment, Ysc.Ledgers.Payment, foreign_key: :payment_id, references: :id

    field :description, :string
    field :amount, Money.Ecto.Composite.Type, default_currency: :USD

    timestamps()
  end
end
