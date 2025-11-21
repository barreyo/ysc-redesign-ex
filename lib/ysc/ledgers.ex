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
  alias Ysc.Ledgers.{LedgerAccount, LedgerEntry, LedgerTransaction, Payment, Refund, Payout}

  # Basic account names for the system
  # Format: {name, account_type, normal_balance, description}
  # Assets and Expenses are debit-normal
  # Liabilities, Revenue, and Equity are credit-normal
  @basic_accounts [
    # Asset accounts (debit-normal)
    {"cash", "asset", "debit", "Cash account for holding funds"},
    {"stripe_account", "asset", "debit", "Stripe account balance"},
    {"accounts_receivable", "asset", "debit", "Outstanding payments from customers"},

    # Liability accounts (credit-normal)
    {"accounts_payable", "liability", "credit", "Outstanding payments to vendors"},
    {"deferred_revenue", "liability", "credit", "Prepaid subscriptions and bookings"},
    {"refund_liability", "liability", "credit", "Pending refunds"},

    # Revenue accounts (credit-normal)
    {"membership_revenue", "revenue", "credit", "Revenue from membership subscriptions"},
    {"event_revenue", "revenue", "credit", "Revenue from event registrations"},
    {"tahoe_booking_revenue", "revenue", "credit", "Revenue from Tahoe cabin bookings"},
    {"clear_lake_booking_revenue", "revenue", "credit", "Revenue from Clear Lake cabin bookings"},
    {"donation_revenue", "revenue", "credit", "Revenue from donations"},

    # Expense accounts (debit-normal)
    {"stripe_fees", "expense", "debit", "Stripe processing fees"},
    {"operating_expenses", "expense", "debit", "General operating expenses"},
    {"refund_expense", "expense", "debit", "Refunds issued to customers"}
  ]

  ## Account Management

  @doc """
  Ensures all basic ledger accounts exist in the system.
  Creates accounts if they don't exist.
  """
  def ensure_basic_accounts do
    Enum.each(@basic_accounts, fn {name, type, normal_balance, description} ->
      case get_account_by_name(name) do
        nil ->
          create_account(%{
            name: name,
            account_type: type,
            normal_balance: normal_balance,
            description: description
          })

        _account ->
          :ok
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
  Creates a refund record.
  """
  def create_refund(attrs \\ %{}) do
    %Refund{}
    |> Refund.changeset(attrs)
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
            :tahoe ->
              "tahoe_booking_revenue"

            :clear_lake ->
              "clear_lake_booking_revenue"

            _ ->
              require Logger

              Logger.error(
                "Booking payment requires property to be specified (tahoe or clear_lake)",
                entity_id: entity_id,
                property: property
              )

              raise "Booking payment requires property to be specified (tahoe or clear_lake)"
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
        debit_credit: :debit,
        description: "Payment receivable from Stripe: #{description}",
        related_entity_type: entity_type,
        related_entity_id: entity_id
      })

    entries = [stripe_receivable_entry | entries]

    # Entry 2: Credit Revenue (explicit credit with positive amount)
    {:ok, revenue_entry} =
      create_entry(%{
        account_id: revenue_account.id,
        payment_id: payment.id,
        amount: amount,
        debit_credit: :credit,
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
            debit_credit: :debit,
            description: "Stripe processing fee for payment #{payment.reference_id}",
            related_entity_type: :administration,
            related_entity_id: payment.id
          })

        # Entry 3b: Credit Stripe Account (reducing receivable by fee amount)
        {:ok, stripe_fee_deduction_entry} =
          create_entry(%{
            account_id: stripe_account.id,
            payment_id: payment.id,
            amount: stripe_fee,
            debit_credit: :credit,
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

      # Check if this refund has already been processed (idempotency)
      if external_refund_id do
        existing_refund = get_refund_by_external_id(external_refund_id)

        if existing_refund do
          require Logger

          Logger.info("Refund already processed, returning existing refund (idempotency)",
            external_refund_id: external_refund_id,
            refund_id: existing_refund.id
          )

          # Find the transaction for this refund
          existing_transaction =
            from(t in LedgerTransaction,
              where: t.refund_id == ^existing_refund.id,
              where: t.type == "refund"
            )
            |> Repo.one()

          # Return the existing refund wrapped in the error tuple for the caller to handle
          Repo.rollback({:already_processed, existing_refund, existing_transaction})
        end
      end

      # Create refund record
      {:ok, refund} =
        create_refund(%{
          payment_id: payment_id,
          user_id: payment.user_id,
          amount: refund_amount,
          external_provider: :stripe,
          external_refund_id: external_refund_id,
          reason: reason,
          status: :completed
        })

      # Create refund transaction
      {:ok, refund_transaction} =
        create_transaction(%{
          type: :refund,
          payment_id: payment_id,
          refund_id: refund.id,
          total_amount: refund_amount,
          status: :completed
        })

      # Create double-entry entries for refund
      entries =
        create_refund_entries(%{
          payment: payment,
          transaction: refund_transaction,
          refund_amount: refund_amount,
          reason: reason
        })

      # Update original payment status if fully refunded
      if Money.equal?(refund_amount, payment.amount) do
        update_payment(payment, %{status: :refunded})
      end

      {refund, refund_transaction, entries}
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
    # Find the revenue entry (should be a credit entry)
    revenue_entry =
      Enum.find(original_entries, fn entry ->
        entry.account.account_type == "revenue" && entry.debit_credit == "credit"
      end)

    stripe_account = get_account_by_name("stripe_account")
    refund_expense_account = get_account_by_name("refund_expense")

    # Entry 1: Debit Refund Expense
    {:ok, refund_expense_entry} =
      create_entry(%{
        account_id: refund_expense_account.id,
        payment_id: payment.id,
        amount: refund_amount,
        debit_credit: :debit,
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
        amount: refund_amount,
        debit_credit: :credit,
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
            amount: refund_amount,
            debit_credit: :debit,
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
  - `currency`: Currency code (optional, defaults to :USD)
  - `status`: Payout status (optional, defaults to "paid")
  - `arrival_date`: When the payout arrives (optional)
  - `metadata`: Additional metadata (optional)
  """
  def process_stripe_payout(attrs) do
    %{
      payout_amount: payout_amount,
      stripe_payout_id: stripe_payout_id,
      description: description
    } = attrs

    currency = Map.get(attrs, :currency, "usd")
    status = Map.get(attrs, :status, "paid")
    arrival_date = Map.get(attrs, :arrival_date)
    metadata = Map.get(attrs, :metadata, %{})

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

      # Create payout record
      {:ok, payout} =
        create_payout(%{
          stripe_payout_id: stripe_payout_id,
          amount: payout_amount,
          currency: currency,
          status: status,
          arrival_date: arrival_date,
          description: description,
          metadata: metadata,
          payment_id: payout_payment.id
        })

      {payout_payment, transaction, entries, payout}
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
        debit_credit: :debit,
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
        amount: payout_amount,
        debit_credit: :credit,
        description: "Stripe payout processed: #{description}",
        related_entity_type: :administration,
        related_entity_id: payment.id
      })

    entries = [stripe_credit_entry | entries]

    entries
  end

  ## Payout Management

  @doc """
  Creates a payout record.
  """
  def create_payout(attrs \\ %{}) do
    %Payout{}
    |> Payout.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a payout by Stripe payout ID.
  """
  def get_payout_by_stripe_id(stripe_payout_id) do
    Repo.get_by(Payout, stripe_payout_id: stripe_payout_id)
  end

  @doc """
  Gets a payout by ID with preloaded payments and refunds.
  """
  def get_payout!(id) do
    Repo.get!(Payout, id)
    |> Repo.preload([:payments, :refunds, :payment])
  end

  @doc """
  Links a payment to a payout.
  """
  def link_payment_to_payout(payout, payment) do
    # Check if already linked
    existing_link =
      from(pp in "payout_payments",
        where: pp.payout_id == ^payout.id and pp.payment_id == ^payment.id,
        limit: 1
      )
      |> Repo.one()

    if existing_link do
      {:ok, payout}
    else
      payout
      |> Repo.preload(:payments)
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:payments, [payment | payout.payments])
      |> Repo.update()
    end
  end

  @doc """
  Links a refund to a payout.
  """
  def link_refund_to_payout(payout, refund) do
    # Check if already linked
    existing_link =
      from(pr in "payout_refunds",
        where: pr.payout_id == ^payout.id and pr.refund_id == ^refund.id,
        limit: 1
      )
      |> Repo.one()

    if existing_link do
      {:ok, payout}
    else
      payout
      |> Repo.preload(:refunds)
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:refunds, [refund | payout.refunds])
      |> Repo.update()
    end
  end

  @doc """
  Gets all payments linked to a payout.
  """
  def get_payout_payments(payout_id) do
    from(p in Payment,
      join: pp in "payout_payments",
      on: pp.payment_id == p.id,
      where: pp.payout_id == ^payout_id,
      preload: [:payment_method]
    )
    |> Repo.all()
  end

  @doc """
  Gets all refunds linked to a payout.
  """
  def get_payout_refunds(payout_id) do
    from(r in Refund,
      join: pr in "payout_refunds",
      on: pr.refund_id == r.id,
      where: pr.payout_id == ^payout_id,
      preload: [:payment, :user]
    )
    |> Repo.all()
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
        debit_credit: :debit,
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
        amount: amount,
        debit_credit: :credit,
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
    entity_id = if revenue_entry, do: revenue_entry.related_entity_id, else: nil

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

    # Get booking if this is a booking payment
    booking =
      if entity_type == :booking && entity_id do
        try do
          Ysc.Bookings.get_booking!(entity_id)
        rescue
          Ecto.NoResultsError -> nil
        end
      else
        nil
      end

    # Get membership subscription if this is a membership payment
    subscription =
      if entity_type == :membership && entity_id do
        Ysc.Subscriptions.get_subscription(entity_id)
      else
        nil
      end

    payment_info = %{
      payment: payment,
      type: determine_payment_type(entity_type),
      ticket_order: ticket_order,
      event: if(ticket_order, do: ticket_order.event, else: nil),
      booking: booking,
      subscription: subscription,
      description:
        build_payment_description(%{
          entity_type: entity_type,
          ticket_order: ticket_order,
          booking: booking,
          subscription: subscription
        })
    }

    payment_info
  end

  defp determine_payment_type(:membership), do: :membership
  defp determine_payment_type(:event), do: :ticket
  defp determine_payment_type(:booking), do: :booking
  defp determine_payment_type(:donation), do: :donation
  defp determine_payment_type(_), do: :unknown

  defp build_payment_description(%{entity_type: :membership, subscription: subscription}) do
    if subscription do
      plan_type = get_membership_plan_type(subscription)
      "Membership Payment - #{String.capitalize(to_string(plan_type))}"
    else
      "Membership Payment"
    end
  end

  defp build_payment_description(%{entity_type: :membership}), do: "Membership Payment"

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

  defp build_payment_description(%{entity_type: :booking, booking: booking})
       when not is_nil(booking) do
    property_name =
      case booking.property do
        :tahoe -> "Tahoe"
        :clear_lake -> "Clear Lake"
        _ -> "Cabin"
      end

    "#{property_name} Booking"
  end

  defp build_payment_description(%{entity_type: :booking}), do: "Cabin Booking"
  defp build_payment_description(%{entity_type: :donation}), do: "Donation"
  defp build_payment_description(_), do: "Payment"

  defp get_membership_plan_type(subscription) do
    case subscription.subscription_items do
      [item | _] ->
        plans = Application.get_env(:ysc, :membership_plans)
        plan = Enum.find(plans, &(&1.stripe_price_id == item.stripe_price_id))
        if plan, do: plan.id, else: :single

      _ ->
        :single
    end
  end

  @doc """
  Gets account balance for a specific account.

  The balance is calculated using explicit debit/credit fields:
  - Debits increase debit-normal accounts (assets, expenses) and decrease credit-normal accounts (revenue, liabilities)
  - Credits decrease debit-normal accounts and increase credit-normal accounts
  """
  def get_account_balance(account_id) do
    account = get_account(account_id)

    entries =
      from(e in LedgerEntry,
        where: e.account_id == ^account_id,
        select: {e.amount, e.debit_credit}
      )
      |> Repo.all()

    # Calculate balance based on debit/credit and account's normal_balance
    balance =
      Enum.reduce(entries, Money.new(0, :USD), fn {entry_amount, debit_credit}, acc ->
        # Determine if this entry increases or decreases the account balance
        increases_balance? =
          case {account.normal_balance, debit_credit} do
            {"debit", "debit"} -> true
            {"debit", "credit"} -> false
            {"credit", "debit"} -> false
            {"credit", "credit"} -> true
            _ -> false
          end

        if increases_balance? do
          case Money.add(acc, entry_amount) do
            {:ok, result} -> result
            {:error, _reason} -> acc
          end
        else
          case Money.sub(acc, entry_amount) do
            {:ok, result} -> result
            {:error, _reason} -> acc
          end
        end
      end)

    balance
  end

  @doc """
  Gets account balance for a specific account within a date range.

  The balance is calculated using explicit debit/credit fields:
  - Debits increase debit-normal accounts (assets, expenses) and decrease credit-normal accounts (revenue, liabilities)
  - Credits decrease debit-normal accounts and increase credit-normal accounts
  """
  def get_account_balance(account_id, start_date, end_date) do
    account = get_account(account_id)

    entries =
      from(e in LedgerEntry,
        join: p in Payment,
        on: e.payment_id == p.id,
        where: e.account_id == ^account_id,
        where: p.payment_date >= ^start_date,
        where: p.payment_date <= ^end_date,
        select: {e.amount, e.debit_credit}
      )
      |> Repo.all()

    # Calculate balance based on debit/credit and account's normal_balance
    balance =
      Enum.reduce(entries, Money.new(0, :USD), fn {entry_amount, debit_credit}, acc ->
        # Determine if this entry increases or decreases the account balance
        increases_balance? =
          case {account.normal_balance, debit_credit} do
            {"debit", "debit"} -> true
            {"debit", "credit"} -> false
            {"credit", "debit"} -> false
            {"credit", "credit"} -> true
            _ -> false
          end

        if increases_balance? do
          case Money.add(acc, entry_amount) do
            {:ok, result} -> result
            {:error, _reason} -> acc
          end
        else
          case Money.sub(acc, entry_amount) do
            {:ok, result} -> result
            {:error, _reason} -> acc
          end
        end
      end)

    balance
  end

  @doc """
  Gets all ledger accounts with their balances.
  """
  def get_accounts_with_balances do
    # First get all accounts
    accounts = Repo.all(LedgerAccount)

    # Then calculate balances for each account
    # Note: get_account_balance already normalizes based on normal_balance
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
    # Note: get_account_balance already normalizes based on normal_balance
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
  Gets a refund by external refund ID.
  """
  def get_refund_by_external_id(external_refund_id) do
    Repo.get_by(Refund, external_refund_id: external_refund_id)
  end

  @doc """
  Gets a refund by ID.
  """
  def get_refund(id) do
    Repo.get(Refund, id)
  end

  @doc """
  Updates a refund record.
  """
  def update_refund(%Refund{} = refund, attrs) do
    refund
    |> Refund.changeset(attrs)
    |> Repo.update()
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
    # Check if this payment is linked to a payout
    payout = get_payout_by_payment_id(payment.id)

    if payout do
      # This is a payout payment
      payment_type_info = %{
        type: "Payout",
        details: "Stripe payout: #{payout.stripe_payout_id}"
      }

      Map.put(payment, :payment_type_info, payment_type_info)
    else
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
  end

  # Helper function to get payout by payment ID
  defp get_payout_by_payment_id(payment_id) do
    from(p in Payout,
      where: p.payment_id == ^payment_id,
      limit: 1
    )
    |> Repo.one()
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
        # Filter for credit entries (revenue entries are credits)
        if entry.debit_credit == "credit", do: entry, else: nil
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

  ## Ledger Integrity

  @doc """
  Verifies that the ledger is balanced (debits = credits).

  In double-entry accounting, the sum of all debits should equal the sum of all credits.
  This function checks that invariant and returns the balance status.

  Returns:
  - `{:ok, :balanced}` if the ledger is balanced
  - `{:error, {:imbalanced, difference}}` if there's an imbalance

  ## Examples

      iex> verify_ledger_balance()
      {:ok, :balanced}

      iex> verify_ledger_balance()
      {:error, {:imbalanced, %Money{amount: 100, currency: :USD}}}

  """
  def verify_ledger_balance do
    require Logger

    # Get total debits (all amounts with debit_credit = 'debit')
    total_debits_query =
      from(e in LedgerEntry,
        where: e.debit_credit == "debit",
        select: sum(fragment("(?.amount).amount", e))
      )

    total_debits_cents = Repo.one(total_debits_query) || Decimal.new(0)

    # Get total credits (all amounts with debit_credit = 'credit')
    total_credits_query =
      from(e in LedgerEntry,
        where: e.debit_credit == "credit",
        select: sum(fragment("(?.amount).amount", e))
      )

    total_credits_cents = Repo.one(total_credits_query) || Decimal.new(0)

    # Convert to Money for proper subtraction
    total_debits = Money.new(total_debits_cents, :USD)
    total_credits = Money.new(total_credits_cents, :USD)

    # In double-entry accounting, total debits should equal total credits
    # Since both are now positive, we subtract credits from debits
    {:ok, balance} = Money.sub(total_debits, total_credits)

    if Money.equal?(balance, Money.new(0, :USD)) do
      Logger.info("Ledger balance verified",
        total_debits: Money.to_string!(total_debits),
        total_credits: Money.to_string!(total_credits),
        balance: "balanced"
      )

      {:ok, :balanced}
    else
      Logger.error("LEDGER IMBALANCE DETECTED!",
        total_debits: Money.to_string!(total_debits),
        total_credits: Money.to_string!(total_credits),
        difference: Money.to_string!(balance)
      )

      {:error, {:imbalanced, balance}}
    end
  end

  @doc """
  Verifies ledger balance and raises if imbalanced.
  Useful for periodic checks and alerts.
  """
  def verify_ledger_balance! do
    case verify_ledger_balance() do
      {:ok, :balanced} ->
        :ok

      {:error, {:imbalanced, difference}} ->
        raise "Ledger imbalance detected! Difference: #{Money.to_string!(difference)}"
    end
  end

  @doc """
  Identifies which accounts are imbalanced by checking the balance of each account.

  In a balanced ledger, each account's total should follow double-entry rules.
  This function helps identify which specific accounts have issues.

  Returns a list of tuples: `{account, balance}` for accounts that have unexpected balances.

  ## Examples

      iex> get_account_balances()
      [
        {%LedgerAccount{name: "stripe_account"}, %Money{amount: 1000, currency: :USD}},
        {%LedgerAccount{name: "cash"}, %Money{amount: 500, currency: :USD}}
      ]

  """
  def get_account_balances do
    # Get all accounts
    accounts = Repo.all(LedgerAccount)

    # Calculate balance for each account
    Enum.map(accounts, fn account ->
      balance = calculate_account_balance(account.id)
      {account, balance}
    end)
    |> Enum.filter(fn {_account, balance} ->
      # Only include accounts with non-zero balances
      not Money.equal?(balance, Money.new(0, :USD))
    end)
    |> Enum.sort_by(fn {_account, balance} -> Money.to_decimal(balance) end, :desc)
  end

  @doc """
  Calculates the balance for a specific account.

  Returns the balance calculated using explicit debit/credit fields.
  """
  def calculate_account_balance(account_id) do
    get_account_balance(account_id)
  end

  # Note: normalize_balance_for_account is no longer needed since we use explicit debit/credit fields
  # All amounts are positive and balances are calculated directly based on debit/credit

  @doc """
  Gets detailed imbalance information including which accounts are off.

  Returns:
  - `{:ok, :balanced}` if balanced
  - `{:error, {:imbalanced, difference, imbalanced_accounts}}` if imbalanced

  The `imbalanced_accounts` will include accounts that have unusual balances
  and could be the source of the imbalance.

  ## Examples

      iex> get_ledger_imbalance_details()
      {:ok, :balanced}

      iex> get_ledger_imbalance_details()
      {:error, {:imbalanced, difference, [
        {%LedgerAccount{name: "stripe_account", account_type: "asset"}, %Money{...}},
        {%LedgerAccount{name: "membership_revenue", account_type: "revenue"}, %Money{...}}
      ]}}

  """
  def get_ledger_imbalance_details do
    require Logger

    case verify_ledger_balance() do
      {:ok, :balanced} = result ->
        result

      {:error, {:imbalanced, difference}} ->
        # Get all account balances to identify problematic accounts
        account_balances = get_account_balances()

        # Group by account type for analysis
        balances_by_type =
          Enum.group_by(account_balances, fn {account, _balance} ->
            account.account_type
          end)

        Logger.error("Ledger imbalance details",
          total_difference: Money.to_string!(difference),
          account_count: length(account_balances),
          asset_accounts: length(Map.get(balances_by_type, "asset", [])),
          liability_accounts: length(Map.get(balances_by_type, "liability", [])),
          revenue_accounts: length(Map.get(balances_by_type, "revenue", [])),
          expense_accounts: length(Map.get(balances_by_type, "expense", []))
        )

        # Log each account with significant balance
        Enum.each(account_balances, fn {account, balance} ->
          Logger.error("Account balance",
            account_name: account.name,
            account_type: account.account_type,
            balance: Money.to_string!(balance)
          )
        end)

        {:error, {:imbalanced, difference, account_balances}}
    end
  end
end
