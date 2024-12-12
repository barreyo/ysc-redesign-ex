defmodule Ysc.Ledgers.LedgerAccount do
  use Ecto.Schema

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "ledger_accounts" do
    field :account_type, LedgerAccountType
    field :name, :string
    field :description, :string

    timestamps()
  end
end
