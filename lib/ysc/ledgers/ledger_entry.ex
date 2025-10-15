defmodule Ysc.Ledgers.LedgerEntry do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "ledger_entries" do
    belongs_to :account, Ysc.Ledgers.LedgerAccount,
      foreign_key: :account_id,
      references: :id

    field :related_entity_type, LedgerEntryEntityType
    field :related_entity_id, Ecto.ULID

    belongs_to :payment, Ysc.Ledgers.Payment, foreign_key: :payment_id, references: :id

    field :description, :string
    field :amount, Money.Ecto.Composite.Type, default_currency: :USD

    timestamps()
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :account_id,
      :related_entity_type,
      :related_entity_id,
      :payment_id,
      :description,
      :amount
    ])
    |> validate_required([:account_id, :amount])
    |> validate_length(:description, max: 1000)
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:payment_id)
  end
end
