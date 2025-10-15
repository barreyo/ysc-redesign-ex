defmodule Ysc.Ledgers do
  @moduledoc """
  The Ledgers context for managing double-entry accounting.

  This module provides utilities for:
  - Creating and managing ledger accounts
  - Processing payments with double-entry bookkeeping
  - Handling refunds and credits
  - Tracking Stripe fees
  - Managing subscription, event, and booking payments
  """

  import Ecto.Query, warn: false
  alias Ysc.Repo
  alias Ysc.Ledgers.{LedgerAccount, LedgerEntry, LedgerTransaction, Payment}

  # Basic account names for the system
  @basic_accounts [
    # Asset accounts
    {"cash", "asset", "Cash account for holding funds"},
    {"stripe_account", "asset", "Stripe account balance"},
    {"accounts_receivable", "asset", "Outstanding payments from customers"},

    # Liability accounts
    {"accounts_payable", "liability", "Outstanding payments to vendors"},
    {"deferred_revenue", "liability", "Prepaid subscriptions and bookings"},
    {"refund_liability", "liability", "Pending refunds"},

    # Revenue accounts
    {"subscription_revenue", "revenue", "Revenue from membership subscriptions"},
    {"event_revenue", "revenue", "Revenue from event registrations"},
    {"booking_revenue", "revenue", "Revenue from cabin bookings"},
    {"donation_revenue", "revenue", "Revenue from donations"},

    # Expense accounts
    {"stripe_fees", "expense", "Stripe processing fees"},
    {"operating_expenses", "expense", "General operating expenses"},
    {"refund_expense", "expense", "Refunds issued to customers"}
  ]

  ## Account Management

  @doc """
  Ensures all basic ledger accounts exist in the system.
  Creates accounts if they don't exist.
  """
  def ensure_basic_accounts do
    Enum.each(@basic_accounts, fn {name, type, description} ->
      case get_account_by_name(name) do
        nil -> create_account(%{name: name, account_type: type, description: description})
        _account -> :ok
      end
    end)
  end

  @doc """
  Gets a ledger account by name.
  """
  def get_account_by_name(name) do
    Repo.get_by(LedgerAccount, name: name)
  end

  @doc """
  Gets a ledger account by ID.
  """
  def get_account(id), do: Repo.get(LedgerAccount, id)

  @doc """
  Creates a new ledger account.
  """
  def create_account(attrs \\ %{}) do
    %LedgerAccount{}
    |> LedgerAccount.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a ledger account.
  """
  def update_account(%LedgerAccount{} = account, attrs) do
    account
    |> LedgerAccount.changeset(attrs)
    |> Repo.update()
  end

  ## Payment Processing

  @doc """
  Processes a payment with double-entry bookkeeping.

  Creates:
  1. A payment record
  2. A ledger transaction
  3. Debit and credit entries

  ## Parameters:
  - `user_id`: The user making the payment
  - `amount`: Payment amount
  - `entity_type`: Type of entity being paid for (event, membership, booking, donation)
  - `entity_id`: ID of the entity being paid for
  - `external_payment_id`: External payment provider ID (e.g., Stripe payment intent)
  - `stripe_fee`: Stripe processing fee (optional)
  - `description`: Description of the payment
  """
  def process_payment(attrs) do
    %{
      user_id: user_id,
      amount: amount,
      entity_type: entity_type,
      entity_id: entity_id,
      external_payment_id: external_payment_id,
      stripe_fee: stripe_fee,
      description: description
    } = attrs

    ensure_basic_accounts()

    Repo.transaction(fn ->
      # Create payment record
      {:ok, payment} =
        create_payment(%{
          user_id: user_id,
          amount: amount,
          external_provider: :stripe,
          external_payment_id: external_payment_id,
          status: :completed,
          payment_date: DateTime.utc_now()
        })

      # Create ledger transaction
      {:ok, transaction} =
        create_transaction(%{
          type: :payment,
          payment_id: payment.id,
          total_amount: amount,
          status: :completed
        })

      # Create double-entry entries
      entries =
        create_payment_entries(%{
          payment: payment,
          transaction: transaction,
          amount: amount,
          entity_type: entity_type,
          entity_id: entity_id,
          stripe_fee: stripe_fee,
          description: description
        })

      {payment, transaction, entries}
    end)
  end

  @doc """
  Creates a payment record.
  """
  def create_payment(attrs \\ %{}) do
    %Payment{}
    |> Payment.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a ledger transaction.
  """
  def create_transaction(attrs \\ %{}) do
    %LedgerTransaction{}
    |> LedgerTransaction.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates double-entry ledger entries for a payment.
  """
  def create_payment_entries(attrs) do
    %{
      payment: payment,
      amount: amount,
      entity_type: entity_type,
      entity_id: entity_id,
      stripe_fee: stripe_fee,
      description: description
    } = attrs

    entries = []

    # Determine revenue account based on entity type
    revenue_account_name =
      case entity_type do
        :membership -> "subscription_revenue"
        :event -> "event_revenue"
        :booking -> "booking_revenue"
        :donation -> "donation_revenue"
        _ -> "subscription_revenue"
      end

    revenue_account = get_account_by_name(revenue_account_name)
    cash_account = get_account_by_name("cash")

    # Entry 1: Debit Cash (Asset)
    {:ok, cash_entry} =
      create_entry(%{
        account_id: cash_account.id,
        payment_id: payment.id,
        amount: amount,
        description: "Payment received: #{description}",
        related_entity_type: entity_type,
        related_entity_id: entity_id
      })

    entries = [cash_entry | entries]

    # Entry 2: Credit Revenue
    {:ok, revenue_entry} =
      create_entry(%{
        account_id: revenue_account.id,
        payment_id: payment.id,
        # Credit (negative)
        amount: elem(Money.mult(amount, -1), 1),
        description: "Revenue from #{entity_type}: #{description}",
        related_entity_type: entity_type,
        related_entity_id: entity_id
      })

    entries = [revenue_entry | entries]

    # Entry 3: If there's a Stripe fee, debit expense and credit cash
    entries =
      if stripe_fee && Money.positive?(stripe_fee) do
        stripe_fee_account = get_account_by_name("stripe_fees")

        {:ok, fee_expense_entry} =
          create_entry(%{
            account_id: stripe_fee_account.id,
            payment_id: payment.id,
            amount: stripe_fee,
            description: "Stripe processing fee for payment #{payment.reference_id}",
            related_entity_type: :administration,
            related_entity_id: payment.id
          })

        {:ok, fee_cash_entry} =
          create_entry(%{
            account_id: cash_account.id,
            payment_id: payment.id,
            # Credit (negative)
            amount: elem(Money.mult(stripe_fee, -1), 1),
            description: "Stripe fee payment for #{payment.reference_id}",
            related_entity_type: :administration,
            related_entity_id: payment.id
          })

        [fee_expense_entry, fee_cash_entry | entries]
      else
        entries
      end

    entries
  end

  @doc """
  Creates a ledger entry.
  """
  def create_entry(attrs \\ %{}) do
    %LedgerEntry{}
    |> LedgerEntry.changeset(attrs)
    |> Repo.insert()
  end

  ## Refund Management

  @doc """
  Processes a refund with double-entry bookkeeping.

  ## Parameters:
  - `payment_id`: Original payment ID
  - `refund_amount`: Amount to refund (can be partial)
  - `reason`: Reason for refund
  - `external_refund_id`: External refund ID from payment provider
  """
  def process_refund(attrs) do
    %{
      payment_id: payment_id,
      refund_amount: refund_amount,
      reason: reason,
      external_refund_id: external_refund_id
    } = attrs

    ensure_basic_accounts()

    Repo.transaction(fn ->
      # Get original payment
      payment = Repo.get!(Payment, payment_id)

      # Create refund transaction
      {:ok, refund_transaction} =
        create_transaction(%{
          type: :refund,
          payment_id: payment_id,
          total_amount: refund_amount,
          status: :completed
        })

      # Create double-entry entries for refund
      entries =
        create_refund_entries(%{
          payment: payment,
          transaction: refund_transaction,
          refund_amount: refund_amount,
          reason: reason,
          external_refund_id: external_refund_id
        })

      # Update original payment status if fully refunded
      if Money.equal?(refund_amount, payment.amount) do
        update_payment(payment, %{status: :refunded})
      end

      {refund_transaction, entries}
    end)
  end

  @doc """
  Creates double-entry ledger entries for a refund.
  """
  def create_refund_entries(attrs) do
    %{
      payment: payment,
      refund_amount: refund_amount,
      reason: reason
    } = attrs

    entries = []

    # Determine original revenue account
    original_entries = get_entries_by_payment(payment.id)
    # Credit entry
    _revenue_entry = Enum.find(original_entries, &(&1.amount.amount < 0))

    cash_account = get_account_by_name("cash")
    refund_expense_account = get_account_by_name("refund_expense")

    # Entry 1: Debit Refund Expense
    {:ok, refund_expense_entry} =
      create_entry(%{
        account_id: refund_expense_account.id,
        payment_id: payment.id,
        amount: refund_amount,
        description: "Refund issued: #{reason}",
        related_entity_type: :administration,
        related_entity_id: payment.id
      })

    entries = [refund_expense_entry | entries]

    # Entry 2: Credit Cash
    {:ok, cash_credit_entry} =
      create_entry(%{
        account_id: cash_account.id,
        payment_id: payment.id,
        # Credit (negative)
        amount: elem(Money.mult(refund_amount, -1), 1),
        description: "Refund payment: #{reason}",
        related_entity_type: :administration,
        related_entity_id: payment.id
      })

    entries = [cash_credit_entry | entries]

    entries
  end

  ## Credit Management

  @doc """
  Adds credit to a user's account.

  ## Parameters:
  - `user_id`: User to credit
  - `amount`: Credit amount
  - `reason`: Reason for credit
  - `entity_type`: Type of entity (optional)
  - `entity_id`: Entity ID (optional)
  """
  def add_credit(attrs) do
    %{
      user_id: user_id,
      amount: amount,
      reason: reason,
      entity_type: entity_type,
      entity_id: entity_id
    } = attrs

    ensure_basic_accounts()

    Repo.transaction(fn ->
      # Create a virtual payment for the credit
      {:ok, credit_payment} =
        create_payment(%{
          user_id: user_id,
          amount: amount,
          external_provider: :stripe,
          external_payment_id: "credit_#{Ecto.ULID.generate()}",
          status: :completed,
          payment_date: DateTime.utc_now()
        })

      # Create transaction
      {:ok, transaction} =
        create_transaction(%{
          type: :adjustment,
          payment_id: credit_payment.id,
          total_amount: amount,
          status: :completed
        })

      # Create double-entry entries
      entries =
        create_credit_entries(%{
          payment: credit_payment,
          transaction: transaction,
          amount: amount,
          reason: reason,
          entity_type: entity_type,
          entity_id: entity_id
        })

      {credit_payment, transaction, entries}
    end)
  end

  @doc """
  Creates double-entry ledger entries for a credit.
  """
  def create_credit_entries(attrs) do
    %{
      payment: payment,
      amount: amount,
      reason: reason,
      entity_type: entity_type,
      entity_id: entity_id
    } = attrs

    entries = []

    cash_account = get_account_by_name("cash")
    accounts_receivable_account = get_account_by_name("accounts_receivable")

    # Entry 1: Debit Accounts Receivable (Asset)
    {:ok, ar_entry} =
      create_entry(%{
        account_id: accounts_receivable_account.id,
        payment_id: payment.id,
        amount: amount,
        description: "Credit issued: #{reason}",
        related_entity_type: entity_type || :administration,
        related_entity_id: entity_id || payment.id
      })

    entries = [ar_entry | entries]

    # Entry 2: Credit Cash (Asset) - This represents the liability to the customer
    {:ok, cash_entry} =
      create_entry(%{
        account_id: cash_account.id,
        payment_id: payment.id,
        # Credit (negative)
        amount: elem(Money.mult(amount, -1), 1),
        description: "Customer credit liability: #{reason}",
        related_entity_type: entity_type || :administration,
        related_entity_id: entity_id || payment.id
      })

    entries = [cash_entry | entries]

    entries
  end

  ## Query Functions

  @doc """
  Gets all ledger entries for a payment.
  """
  def get_entries_by_payment(payment_id) do
    from(e in LedgerEntry,
      where: e.payment_id == ^payment_id,
      preload: [:account]
    )
    |> Repo.all()
  end

  @doc """
  Gets all payments for a user.
  """
  def get_payments_by_user(user_id) do
    from(p in Payment,
      where: p.user_id == ^user_id,
      order_by: [desc: p.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Gets account balance for a specific account.
  """
  def get_account_balance(account_id) do
    entries =
      from(e in LedgerEntry,
        where: e.account_id == ^account_id,
        select: e.amount
      )
      |> Repo.all()

    # Sum the money amounts manually
    Enum.reduce(entries, Money.new(0, :USD), fn entry_amount, acc ->
      case Money.add(acc, entry_amount) do
        {:ok, result} -> result
        # If addition fails, keep the accumulator
        {:error, _reason} -> acc
      end
    end)
  end

  @doc """
  Gets all ledger accounts with their balances.
  """
  def get_accounts_with_balances do
    # First get all accounts
    accounts = Repo.all(LedgerAccount)

    # Then calculate balances for each account
    Enum.map(accounts, fn account ->
      balance = get_account_balance(account.id)
      %{account: account, balance: balance}
    end)
  end

  @doc """
  Updates a payment.
  """
  def update_payment(%Payment{} = payment, attrs) do
    payment
    |> Payment.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Gets a payment by ID.
  """
  def get_payment(id), do: Repo.get(Payment, id)

  @doc """
  Gets a payment by external payment ID.
  """
  def get_payment_by_external_id(external_payment_id) do
    Repo.get_by(Payment, external_payment_id: external_payment_id)
  end
end
