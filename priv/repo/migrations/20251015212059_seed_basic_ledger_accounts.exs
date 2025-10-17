defmodule Ysc.Repo.Migrations.SeedBasicLedgerAccounts do
  use Ecto.Migration

  def up do
    # Basic account names for the system
    basic_accounts = [
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

    # Insert basic accounts
    Enum.each(basic_accounts, fn {name, account_type, description} ->
      execute """
        INSERT INTO ledger_accounts (id, account_type, name, description, inserted_at, updated_at)
        VALUES (
          gen_random_uuid(),
          '#{account_type}',
          '#{name}',
          '#{description}',
          NOW(),
          NOW()
        )
        ON CONFLICT (account_type, name) DO NOTHING;
      """
    end)
  end

  def down do
    # Remove basic accounts
    execute """
      DELETE FROM ledger_accounts
      WHERE name IN (
        'cash', 'stripe_account', 'accounts_receivable',
        'accounts_payable', 'deferred_revenue', 'refund_liability',
        'membership_revenue', 'event_revenue', 'booking_revenue',
        'tahoe_booking_revenue', 'clear_lake_booking_revenue', 'donation_revenue',
        'stripe_fees', 'operating_expenses', 'refund_expense'
      );
    """
  end
end
