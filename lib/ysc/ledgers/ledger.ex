defmodule Ysc.Ledgers.Ledger do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ledgers" do
    field :name, :string
    field :description, :string
    field :ledger_type, LedgerType

    timestamps()
  end

  def insert_ledger_changeset(ledger, attrs) do
    ledger
    |> cast(attrs, [:name, :description, :ledger_type])
    |> validate_required([:name, :ledger_type])
  end
end
