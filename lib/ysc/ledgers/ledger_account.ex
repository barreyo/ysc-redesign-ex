defmodule Ysc.Ledgers.LedgerAccount do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "ledger_accounts" do
    field :account_type, LedgerAccountType
    field :name, :string
    field :description, :string

    timestamps()
  end

  def changeset(account, attrs) do
    account
    |> cast(attrs, [:account_type, :name, :description])
    |> validate_required([:account_type, :name])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:description, max: 1000)
    |> unique_constraint(:name)
  end
end
