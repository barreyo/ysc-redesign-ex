defmodule Ysc.Ledgers do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Ysc.Repo

  alias Ysc.Ledgers.{Ledger, LedgerAccount, AccountTransaction}

  @spec get_ledger_by_id(any()) :: any()
  def get_ledger_by_id(id) do
    Repo.get_by(Ledger, id: id)
  end

  def get_ledger_account_by_id(id) do
    Repo.get_by(LedgerAccount, id: id)
  end

  def get_ledger_account_by_name(name) do
    Repo.get_by(LedgerAccount, name: name)
  end

  @spec insert_ledger(
          :invalid
          | %{optional(:__struct__) => none(), optional(atom() | binary()) => any()}
        ) :: any()
  def insert_ledger(attrs) do
    %Ledger{}
    |> Ledger.insert_ledger_changeset(attrs)
    |> Repo.insert()
  end

  @spec add_account_transaction(any(), any(), any(), any()) :: any()
  def add_account_transaction(account_id, ledger_id, transaction_type, amount, description \\ "") do
    %AccountTransaction{}
    |> AccountTransaction.insert_account_transaction_changeset(%{
      account_id: account_id,
      ledger_id: ledger_id,
      transaction_type: transaction_type,
      amount: amount,
      description: description
    })
    |> Repo.insert()
  end

  def debit_ledger_account(account_id, ledger_id, amount, description \\ "") do
    add_account_transaction(
      account_id,
      ledger_id,
      "credit",
      amount,
      description
    )
  end

  def credit_ledger_account(account_id, ledger_id, amount, description \\ "") do
    add_account_transaction(
      account_id,
      ledger_id,
      "debit",
      amount,
      description
    )
  end

  def get_or_create_internal_ledger_account(attrs) do
    {:ok, entry} =
      %LedgerAccount{}
      |> LedgerAccount.ledger_internal_account_changeset(attrs)
      |> Repo.insert(returning: true, on_conflict: :nothing)

    get_ledger_account_by_name(entry.name)
  end

  def get_or_create_user_ledger_account(attrs) do
    {:ok, entry} =
      %LedgerAccount{}
      |> LedgerAccount.ledger_user_account_changeset(attrs)
      |> Repo.insert(returning: true, on_conflict: :nothing)

    get_ledger_account_by_name(entry.name)
  end
end
