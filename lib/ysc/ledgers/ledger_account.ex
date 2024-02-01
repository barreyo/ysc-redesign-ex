defmodule Ysc.Ledgers.LedgerAccount do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ledger_accounts" do
    field :account_type, LedgerAccountType
    field :name, :string
    field :description, :string
    belongs_to :user, Ysc.Accounts.User, foreign_key: :user_id, references: :id, type: Ecto.ULID

    timestamps()
  end

  @spec ledger_internal_account_changeset(
          {map(), map()}
          | %{
              :__struct__ => atom() | %{:__changeset__ => map(), optional(any()) => any()},
              optional(atom()) => any()
            },
          map()
        ) :: Ecto.Changeset.t()
  def ledger_internal_account_changeset(ledger_account, attrs) do
    ledger_account
    |> cast(attrs |> Map.put(:account_type, "internal"), [
      :account_type,
      :name,
      :description
    ])
    |> validate_required([:account_type, :name])
  end

  def ledger_user_account_changeset(ledger_account, attrs) do
    ledger_account
    |> cast(attrs |> Map.put(:account_type, "user"), [
      :account_type,
      :name,
      :description,
      :user_id
    ])
    |> cast_assoc(:user)
    |> assoc_constraint(:user)
    |> validate_required([:account_type, :name])
  end
end
