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
    {"membership_revenue", "revenue", "Revenue from membership subscriptions"},
    {"event_revenue", "revenue", "Revenue from event registrations"},
    {"booking_revenue", "revenue", "Revenue from cabin bookings"},
    {"tahoe_booking_revenue", "revenue", "Revenue from Tahoe cabin bookings"},
    {"clear_lake_booking_revenue", "revenue", "Revenue from Clear Lake cabin bookings"},
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
  - `property`: Property for booking payments (:tahoe, :clear_lake, or nil)
  - `payment_method_id`: ID of the payment method used (optional)
  """
  def process_payment(attrs) do
    %{
      user_id: user_id,
      amount: amount,
      entity_type: entity_type,
      entity_id: entity_id,
      external_payment_id: external_payment_id,
      stripe_fee: stripe_fee,
      description: description,
      property: property,
      payment_method_id: payment_method_id
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
          payment_date: DateTime.utc_now(),
          payment_method_id: payment_method_id
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
          description: description,
          property: property
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
      description: description,
      property: property
    } = attrs

    entries = []

    # Determine revenue account based on entity type and property
    revenue_account_name =
      case entity_type do
        :membership ->
          "membership_revenue"

        :event ->
          "event_revenue"

        :booking ->
          case property do
            :tahoe -> "tahoe_booking_revenue"
            :clear_lake -> "clear_lake_booking_revenue"
            # fallback to general booking revenue
            _ -> "booking_revenue"
          end

        :donation ->
          "donation_revenue"

        _ ->
          "membership_revenue"
      end

    revenue_account = get_account_by_name(revenue_account_name)
    stripe_receivable_account = get_account_by_name("stripe_account")

    # Entry 1: Debit Stripe Receivable (Asset) - money owed to us by Stripe
    {:ok, stripe_receivable_entry} =
      create_entry(%{
        account_id: stripe_receivable_account.id,
        payment_id: payment.id,
        amount: amount,
        description: "Payment receivable from Stripe: #{description}",
        related_entity_type: entity_type,
        related_entity_id: entity_id
      })

    entries = [stripe_receivable_entry | entries]

    # Entry 2: Credit Revenue (positive amount for revenue)
    {:ok, revenue_entry} =
      create_entry(%{
        account_id: revenue_account.id,
        payment_id: payment.id,
        amount: amount,
        description: "Revenue from #{entity_type}: #{description}",
        related_entity_type: entity_type,
        related_entity_id: entity_id
      })

    entries = [revenue_entry | entries]

    # Entry 3: If there's a Stripe fee, track the flow through Stripe account
    entries =
      if stripe_fee && Money.positive?(stripe_fee) do
        stripe_fee_account = get_account_by_name("stripe_fees")
        stripe_account = get_account_by_name("stripe_account")

        # Entry 3a: Debit Stripe Fee Expense
        {:ok, fee_expense_entry} =
          create_entry(%{
            account_id: stripe_fee_account.id,
            payment_id: payment.id,
            amount: stripe_fee,
            description: "Stripe processing fee for payment #{payment.reference_id}",
            related_entity_type: :administration,
            related_entity_id: payment.id
          })

        # Entry 3b: Credit Stripe Account (reducing receivable by fee amount)
        {:ok, stripe_fee_deduction_entry} =
          create_entry(%{
            account_id: stripe_account.id,
            payment_id: payment.id,
            # Credit (negative) - reducing our receivable by the fee amount
            amount: elem(Money.mult(stripe_fee, -1), 1),
            description: "Stripe fee deduction from receivable - #{payment.reference_id}",
            related_entity_type: :administration,
            related_entity_id: payment.id
          })

        [fee_expense_entry, stripe_fee_deduction_entry | entries]
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
    # Find the revenue entry (should be positive now)
    revenue_entry =
      Enum.find(original_entries, fn entry ->
        entry.account.account_type == "revenue" && entry.amount.amount > 0
      end)

    stripe_account = get_account_by_name("stripe_account")
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

    # Entry 2: Credit Stripe Account (increasing our receivable - we owe Stripe for the refund)
    {:ok, stripe_credit_entry} =
      create_entry(%{
        account_id: stripe_account.id,
        payment_id: payment.id,
        # Credit (negative) - increasing our liability to Stripe
        amount: elem(Money.mult(refund_amount, -1), 1),
        description: "Refund processed through Stripe: #{reason}",
        related_entity_type: :administration,
        related_entity_id: payment.id
      })

    entries = [stripe_credit_entry | entries]

    # Entry 3: Reverse the original revenue (if we found the revenue entry)
    entries =
      if revenue_entry do
        {:ok, revenue_reversal_entry} =
          create_entry(%{
            account_id: revenue_entry.account_id,
            payment_id: payment.id,
            # Credit (negative) - reversing the original revenue
            amount: elem(Money.mult(refund_amount, -1), 1),
            description: "Revenue reversal for refund: #{reason}",
            related_entity_type: :administration,
            related_entity_id: payment.id
          })

        [revenue_reversal_entry | entries]
      else
        entries
      end

    entries
  end

  ## Stripe Payout Management

  @doc """
  Processes a Stripe payout - moves money from Stripe receivable to Cash.

  ## Parameters:
  - `payout_amount`: Amount being paid out by Stripe
  - `stripe_payout_id`: Stripe payout ID
  - `description`: Description of the payout
  """
  def process_stripe_payout(attrs) do
    %{
      payout_amount: payout_amount,
      stripe_payout_id: stripe_payout_id,
      description: description
    } = attrs

    ensure_basic_accounts()

    Repo.transaction(fn ->
      # Create a virtual payment record for the payout
      {:ok, payout_payment} =
        create_payment(%{
          # System payout, not user-specific
          user_id: nil,
          amount: payout_amount,
          external_provider: :stripe,
          external_payment_id: stripe_payout_id,
          status: :completed,
          payment_date: DateTime.utc_now()
        })

      # Create transaction
      {:ok, transaction} =
        create_transaction(%{
          type: :payout,
          payment_id: payout_payment.id,
          total_amount: payout_amount,
          status: :completed
        })

      # Create double-entry entries
      entries =
        create_payout_entries(%{
          payment: payout_payment,
          transaction: transaction,
          payout_amount: payout_amount,
          description: description
        })

      {payout_payment, transaction, entries}
    end)
  end

  @doc """
  Creates double-entry ledger entries for a Stripe payout.
  """
  def create_payout_entries(attrs) do
    %{
      payment: payment,
      payout_amount: payout_amount,
      description: description
    } = attrs

    entries = []

    cash_account = get_account_by_name("cash")
    stripe_account = get_account_by_name("stripe_account")

    # Entry 1: Debit Cash (Asset) - money coming into our bank account
    {:ok, cash_entry} =
      create_entry(%{
        account_id: cash_account.id,
        payment_id: payment.id,
        amount: payout_amount,
        description: "Stripe payout received: #{description}",
        related_entity_type: :administration,
        related_entity_id: payment.id
      })

    entries = [cash_entry | entries]

    # Entry 2: Credit Stripe Account (Asset) - reducing our receivable
    {:ok, stripe_credit_entry} =
      create_entry(%{
        account_id: stripe_account.id,
        payment_id: payment.id,
        # Credit (negative) - reducing our receivable
        amount: elem(Money.mult(payout_amount, -1), 1),
        description: "Stripe payout processed: #{description}",
        related_entity_type: :administration,
        related_entity_id: payment.id
      })

    entries = [stripe_credit_entry | entries]

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
  Gets all payments for a specific subscription.
  Returns payments ordered by payment_date descending.
  """
  def get_payments_for_subscription(subscription_id) do
    from(p in Payment,
      join: e in LedgerEntry,
      on: e.payment_id == p.id,
      where: e.related_entity_type == "membership",
      where: e.related_entity_id == ^subscription_id,
      preload: [:payment_method],
      order_by: [desc: p.payment_date],
      distinct: true
    )
    |> Repo.all()
  end

  @doc """
  Gets paginated payments for a user with ticket order and membership information.
  Returns payments ordered by payment_date descending.
  """
  def list_user_payments_paginated(user_id, page \\ 1, per_page \\ 20) do
    offset = (page - 1) * per_page

    payments =
      from(p in Payment,
        where: p.user_id == ^user_id,
        preload: [:payment_method],
        order_by: [desc: p.payment_date],
        limit: ^per_page,
        offset: ^offset
      )
      |> Repo.all()
      |> Enum.map(&enrich_payment_with_details/1)

    total_count =
      from(p in Payment,
        where: p.user_id == ^user_id,
        select: count()
      )
      |> Repo.one()

    {payments, total_count}
  end

  defp enrich_payment_with_details(payment) do
    # Get the revenue ledger entry to determine payment type
    revenue_entry = get_revenue_entry_for_payment(payment.id)
    entity_type = if revenue_entry, do: revenue_entry.related_entity_type, else: nil

    # Get ticket order if this is an event payment
    ticket_order =
      if entity_type == :event do
        case from(to in Ysc.Tickets.TicketOrder,
               where: to.payment_id == ^payment.id,
               preload: [:event, tickets: :ticket_tier]
             )
             |> Repo.one() do
          nil -> nil
          order -> Repo.preload(order, [:event, tickets: :ticket_tier])
        end
      else
        nil
      end

    payment_info = %{
      payment: payment,
      type: determine_payment_type(entity_type),
      ticket_order: ticket_order,
      event: if(ticket_order, do: ticket_order.event, else: nil),
      description:
        build_payment_description(%{
          entity_type: entity_type,
          ticket_order: ticket_order
        })
    }

    payment_info
  end

  defp determine_payment_type(:membership), do: :membership
  defp determine_payment_type(:event), do: :ticket
  defp determine_payment_type(:booking), do: :booking
  defp determine_payment_type(:donation), do: :donation
  defp determine_payment_type(_), do: :unknown

  defp build_payment_description(%{entity_type: :membership}) do
    "Membership Payment"
  end

  defp build_payment_description(%{entity_type: :event, ticket_order: ticket_order})
       when not is_nil(ticket_order) do
    event = ticket_order.event
    ticket_count = length(ticket_order.tickets || [])
    ticket_text = if ticket_count == 1, do: "ticket", else: "tickets"

    if event do
      "#{event.title} - #{ticket_count} #{ticket_text}"
    else
      "Event Tickets - #{ticket_count} #{ticket_text}"
    end
  end

  defp build_payment_description(%{entity_type: :booking}), do: "Cabin Booking"
  defp build_payment_description(%{entity_type: :donation}), do: "Donation"
  defp build_payment_description(_), do: "Payment"

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
  Gets account balance for a specific account within a date range.
  """
  def get_account_balance(account_id, start_date, end_date) do
    entries =
      from(e in LedgerEntry,
        join: p in Payment,
        on: e.payment_id == p.id,
        where: e.account_id == ^account_id,
        where: p.payment_date >= ^start_date,
        where: p.payment_date <= ^end_date,
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
  Gets all ledger accounts with their balances within a date range.
  """
  def get_accounts_with_balances(start_date, end_date) do
    # First get all accounts
    accounts = Repo.all(LedgerAccount)

    # Then calculate balances for each account within the date range
    Enum.map(accounts, fn account ->
      balance = get_account_balance(account.id, start_date, end_date)
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
  Gets a payment by ID with preloaded associations.
  """
  def get_payment_with_associations(id) do
    Repo.get(Payment, id)
    |> case do
      nil -> nil
      payment -> Repo.preload(payment, [:user, :payment_method])
    end
  end

  @doc """
  Gets a payment by external payment ID.
  """
  def get_payment_by_external_id(external_payment_id) do
    Repo.get_by(Payment, external_payment_id: external_payment_id)
  end

  @doc """
  Gets recent payments within a date range.
  """
  def get_recent_payments(start_date, end_date, limit \\ 50) do
    from(p in Payment,
      preload: [:user, :payment_method],
      where: p.payment_date >= ^start_date,
      where: p.payment_date <= ^end_date,
      order_by: [desc: p.payment_date],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.map(&add_payment_type_info/1)
  end

  @doc """
  Gets recent payments with payment type information.
  """
  def get_recent_payments_with_types(start_date, end_date, limit \\ 50) do
    from(p in Payment,
      preload: [:user, :payment_method],
      where: p.payment_date >= ^start_date,
      where: p.payment_date <= ^end_date,
      order_by: [desc: p.payment_date],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.map(&add_payment_type_info/1)
  end

  @doc """
  Adds payment type information to a payment struct.
  """
  def add_payment_type_info(payment) do
    # Get the revenue entry for this payment to determine the type
    revenue_entry = get_revenue_entry_for_payment(payment.id)

    payment_type_info =
      case revenue_entry do
        nil ->
          %{type: "Unknown", details: "No revenue entry found"}

        entry ->
          case entry.related_entity_type do
            :membership ->
              %{type: "Membership", details: get_membership_details(entry.related_entity_id)}

            :event ->
              %{type: "Event", details: get_event_details(entry.related_entity_id)}

            :booking ->
              %{
                type: "Booking",
                details: get_booking_details(entry.related_entity_id, entry.account.name)
              }

            :donation ->
              %{type: "Donation", details: "General donation"}

            :administration ->
              %{type: "Administration", details: "System transaction"}

            _ ->
              %{type: "Unknown", details: "Unknown entity type"}
          end
      end

    Map.put(payment, :payment_type_info, payment_type_info)
  end

  # Helper function to get the revenue entry for a payment
  defp get_revenue_entry_for_payment(payment_id) do
    from(e in LedgerEntry,
      join: a in LedgerAccount,
      on: e.account_id == a.id,
      where: e.payment_id == ^payment_id,
      where: a.account_type == "revenue",
      preload: [:account],
      limit: 1
    )
    |> Repo.one()
    |> case do
      nil ->
        nil

      entry ->
        # Filter for positive amounts in Elixir since we can't do it in the query
        if entry.amount.amount > 0, do: entry, else: nil
    end
  end

  # Helper function to get membership details
  defp get_membership_details(subscription_id) when is_binary(subscription_id) do
    case Ysc.Subscriptions.get_subscription(subscription_id) do
      nil ->
        "Unknown membership"

      subscription ->
        # Get subscription items to find the price ID
        # Preload subscription items and get the first one
        subscription_with_items = Ysc.Repo.preload(subscription, :subscription_items)

        case subscription_with_items.subscription_items do
          [] ->
            "Membership"

          [item | _] ->
            # Map price ID to membership plan
            get_membership_plan_by_price_id(item.stripe_price_id)
        end
    end
  end

  defp get_membership_details(_), do: "Membership"

  # Helper function to get membership plan by price ID
  defp get_membership_plan_by_price_id(price_id) when is_binary(price_id) do
    membership_plans = Application.get_env(:ysc, :membership_plans, [])

    case Enum.find(membership_plans, fn plan -> plan.stripe_price_id == price_id end) do
      nil ->
        "Membership"

      plan ->
        "#{plan.name} Membership"
    end
  end

  defp get_membership_plan_by_price_id(_), do: "Membership"

  # Helper function to get event details
  defp get_event_details(event_id) when is_binary(event_id) do
    try do
      event = Ysc.Events.get_event!(event_id)
      event.title
    rescue
      Ecto.NoResultsError -> "Unknown Event"
    end
  end

  defp get_event_details(_), do: "Event"

  # Helper function to get booking details
  defp get_booking_details(booking_id, account_name) when is_binary(booking_id) do
    property =
      case account_name do
        "tahoe_booking_revenue" -> "Tahoe"
        "clear_lake_booking_revenue" -> "Clear Lake"
        _ -> "Unknown Property"
      end

    # Try to get booking details if we have a booking system
    # For now, just return the property
    "#{property} Booking"
  end

  defp get_booking_details(_, account_name) do
    property =
      case account_name do
        "tahoe_booking_revenue" -> "Tahoe"
        "clear_lake_booking_revenue" -> "Clear Lake"
        _ -> "Unknown Property"
      end

    "#{property} Booking"
  end
end
