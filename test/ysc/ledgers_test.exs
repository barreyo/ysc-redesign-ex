defmodule Ysc.LedgersTest do
  use Ysc.DataCase, async: true

  alias Ysc.Ledgers
  alias Ysc.Ledgers.{LedgerAccount, LedgerTransaction, Payment, Refund}
  import Ysc.AccountsFixtures

  describe "ledger account management" do
    test "ensure_basic_accounts/0 creates all basic accounts" do
      Ledgers.ensure_basic_accounts()

      # Check that basic accounts exist
      assert Ledgers.get_account_by_name("cash")
      assert Ledgers.get_account_by_name("membership_revenue")
      assert Ledgers.get_account_by_name("event_revenue")
      assert Ledgers.get_account_by_name("tahoe_booking_revenue")
      assert Ledgers.get_account_by_name("clear_lake_booking_revenue")
      assert Ledgers.get_account_by_name("donation_revenue")
      assert Ledgers.get_account_by_name("stripe_fees")
      assert Ledgers.get_account_by_name("refund_expense")
    end

    test "get_accounts_with_balances/0 returns accounts with balances" do
      Ledgers.ensure_basic_accounts()

      accounts_with_balances = Ledgers.get_accounts_with_balances()

      assert is_list(accounts_with_balances)
      assert length(accounts_with_balances) > 0

      # Check structure
      [first_account | _] = accounts_with_balances
      assert Map.has_key?(first_account, :account)
      assert Map.has_key?(first_account, :balance)
      assert %LedgerAccount{} = first_account.account
    end
  end

  describe "payment processing" do
    setup do
      user = user_fixture()
      Ledgers.ensure_basic_accounts()

      # Configure QuickBooks client to use mock (prevents errors when sync jobs run)
      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      # Set up QuickBooks configuration for tests
      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      # Set up default mocks for automatic sync jobs
      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      %{user: user}
    end

    test "process_payment/1 creates payment with double-entry entries", %{user: user} do
      # $50.00
      amount = Money.new(5000, :USD)
      # $1.75
      stripe_fee = Money.new(175, :USD)

      payment_attrs = %{
        user_id: user.id,
        amount: amount,
        entity_type: :membership,
        entity_id: Ecto.ULID.generate(),
        external_payment_id: "pi_test_123",
        stripe_fee: stripe_fee,
        description: "Test membership payment",
        property: nil,
        payment_method_id: nil
      }

      assert {:ok, {payment, transaction, entries}} = Ledgers.process_payment(payment_attrs)

      # Check payment was created
      assert %Payment{} = payment
      assert payment.amount == amount
      assert payment.external_payment_id == "pi_test_123"
      assert payment.status == :completed

      # Check transaction was created
      assert %LedgerTransaction{} = transaction
      assert transaction.type == :payment
      assert transaction.total_amount == amount
      assert transaction.status == :completed

      # Check entries were created (should be 4: cash debit, revenue credit, fee debit, fee credit)
      assert length(entries) == 4

      # Verify all entries have the correct payment_id
      Enum.each(entries, fn entry ->
        assert entry.payment_id == payment.id
      end)
    end

    test "get_account_balance/1 calculates correct balance" do
      Ledgers.ensure_basic_accounts()
      cash_account = Ledgers.get_account_by_name("cash")

      # Initially should be zero
      balance = Ledgers.get_account_balance(cash_account.id)
      assert Money.equal?(balance, Money.new(0, :USD))
    end
  end

  describe "refund processing" do
    setup do
      user = user_fixture()
      Ledgers.ensure_basic_accounts()

      # Configure QuickBooks client to use mock (prevents errors when sync jobs run)
      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      # Set up QuickBooks configuration for tests
      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      # Set up default mocks for automatic sync jobs
      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      # Create a test payment first
      amount = Money.new(5000, :USD)

      payment_attrs = %{
        user_id: user.id,
        amount: amount,
        entity_type: :membership,
        entity_id: Ecto.ULID.generate(),
        external_payment_id: "pi_test_123",
        stripe_fee: Money.new(175, :USD),
        description: "Test membership payment",
        property: nil,
        payment_method_id: nil
      }

      {:ok, {payment, _transaction, _entries}} = Ledgers.process_payment(payment_attrs)

      %{user: user, payment: payment}
    end

    test "process_refund/1 creates refund entries", %{payment: payment} do
      # $25.00
      refund_amount = Money.new(2500, :USD)

      refund_attrs = %{
        payment_id: payment.id,
        refund_amount: refund_amount,
        reason: "Customer requested partial refund",
        external_refund_id: "re_test_123"
      }

      assert {:ok, {refund, refund_transaction, entries}} = Ledgers.process_refund(refund_attrs)

      # Check refund record was created
      assert %Refund{} = refund
      assert refund.amount == refund_amount
      assert refund.status == :completed
      assert refund.reason == "Customer requested partial refund"
      assert refund.external_refund_id == "re_test_123"
      assert refund.external_provider == :stripe
      assert refund.user_id == payment.user_id
      assert refund.payment_id == payment.id

      # Check refund transaction was created
      assert %LedgerTransaction{} = refund_transaction
      assert refund_transaction.type == :refund
      assert refund_transaction.total_amount == refund_amount
      assert refund_transaction.status == :completed
      assert refund_transaction.refund_id == refund.id
      assert refund_transaction.payment_id == payment.id

      # Check entries were created
      # Should have at least: refund expense debit, stripe account credit
      # If revenue entry found, also creates: revenue reversal debit, stripe account credit (for revenue reversal)
      # So total can be 2 (no revenue entry) or 4 (with revenue entry)
      assert length(entries) >= 2
      assert length(entries) <= 4

      # Verify all entries have the correct payment_id
      Enum.each(entries, fn entry ->
        assert entry.payment_id == payment.id
      end)

      # Verify we have a refund expense entry (debit - positive amount, debit_credit: :debit)
      refund_expense_entry =
        Enum.find(entries, fn e ->
          e.description =~ "Refund issued" &&
            e.debit_credit == :debit &&
            Money.positive?(e.amount)
        end)

      assert refund_expense_entry != nil
      assert refund_expense_entry.amount == refund_amount
      assert refund_expense_entry.debit_credit == :debit

      # Verify we have a stripe account credit entry (credit - positive amount, debit_credit: :credit)
      stripe_credit_entry =
        Enum.find(entries, fn e ->
          e.description =~ "Refund processed through Stripe" &&
            e.debit_credit == :credit &&
            Money.positive?(e.amount)
        end)

      assert stripe_credit_entry != nil
      assert Money.equal?(stripe_credit_entry.amount, refund_amount)
      assert stripe_credit_entry.debit_credit == :credit
    end
  end

  describe "event payment with donations" do
    setup do
      user = user_fixture()
      Ledgers.ensure_basic_accounts()

      # Configure QuickBooks client to use mock (prevents errors when sync jobs run)
      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      # Set up QuickBooks configuration for tests
      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      # Set up default mocks for automatic sync jobs
      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      %{user: user}
    end

    test "process_event_payment_with_donations/1 creates separate revenue entries for event and donation",
         %{
           user: user
         } do
      # $100.00 total: $60.00 event + $40.00 donation
      total_amount = Money.new(10_000, :USD)
      event_amount = Money.new(6_000, :USD)
      donation_amount = Money.new(4_000, :USD)
      stripe_fee = Money.new(320, :USD)
      event_id = Ecto.ULID.generate()

      payment_attrs = %{
        user_id: user.id,
        total_amount: total_amount,
        event_amount: event_amount,
        donation_amount: donation_amount,
        event_id: event_id,
        external_payment_id: "pi_mixed_123",
        stripe_fee: stripe_fee,
        description: "Event tickets with donation - Order ORD123",
        payment_method_id: nil
      }

      assert {:ok, {payment, transaction, entries}} =
               Ledgers.process_event_payment_with_donations(payment_attrs)

      # Check payment was created
      assert %Payment{} = payment
      assert payment.amount == total_amount
      assert payment.external_payment_id == "pi_mixed_123"
      assert payment.status == :completed

      # Check transaction was created
      assert %LedgerTransaction{} = transaction
      assert transaction.type == :payment
      assert transaction.total_amount == total_amount
      assert transaction.status == :completed

      # Check entries were created
      # Should have: stripe receivable debit, event revenue credit, donation revenue credit,
      # stripe fee debit, stripe account credit (for fee)
      assert length(entries) == 5

      # Verify all entries have the correct payment_id
      Enum.each(entries, fn entry ->
        assert entry.payment_id == payment.id
      end)

      # Verify Stripe receivable entry (debit)
      stripe_receivable_entry =
        Enum.find(entries, fn e ->
          e.description =~ "Payment receivable from Stripe" && e.debit_credit == :debit
        end)

      assert stripe_receivable_entry != nil
      assert stripe_receivable_entry.amount == total_amount
      assert stripe_receivable_entry.related_entity_type in [:event, "event"]
      assert stripe_receivable_entry.related_entity_id == event_id

      # Verify event revenue entry (credit)
      event_revenue_entry =
        Enum.find(entries, fn e ->
          e.description =~ "Event revenue from tickets" && e.debit_credit == :credit
        end)

      assert event_revenue_entry != nil
      assert event_revenue_entry.amount == event_amount
      assert event_revenue_entry.related_entity_type in [:event, "event"]
      assert event_revenue_entry.related_entity_id == event_id

      # Verify donation revenue entry (credit)
      donation_revenue_entry =
        Enum.find(entries, fn e ->
          e.description =~ "Donation revenue from tickets" && e.debit_credit == :credit
        end)

      assert donation_revenue_entry != nil
      assert donation_revenue_entry.amount == donation_amount
      assert donation_revenue_entry.related_entity_type in [:donation, "donation"]
      assert donation_revenue_entry.related_entity_id == event_id

      # Verify Stripe fee entries
      fee_expense_entry =
        Enum.find(entries, fn e ->
          e.description =~ "Stripe processing fee" && e.debit_credit == :debit
        end)

      assert fee_expense_entry != nil
      assert fee_expense_entry.amount == stripe_fee

      # Verify ledger balance
      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end

    test "process_event_payment_with_donations/1 handles donation-only payments", %{user: user} do
      # $50.00 donation only (no event tickets)
      total_amount = Money.new(5_000, :USD)
      event_amount = Money.new(0, :USD)
      donation_amount = Money.new(5_000, :USD)
      stripe_fee = Money.new(160, :USD)
      event_id = Ecto.ULID.generate()

      payment_attrs = %{
        user_id: user.id,
        total_amount: total_amount,
        event_amount: event_amount,
        donation_amount: donation_amount,
        event_id: event_id,
        external_payment_id: "pi_donation_only_123",
        stripe_fee: stripe_fee,
        description: "Donation only - Order ORD456",
        payment_method_id: nil
      }

      assert {:ok, {payment, _transaction, entries}} =
               Ledgers.process_event_payment_with_donations(payment_attrs)

      # Check payment was created
      assert %Payment{} = payment
      assert payment.amount == total_amount

      # Check entries - should NOT have event revenue entry
      event_revenue_entry =
        Enum.find(entries, fn e ->
          e.description =~ "Event revenue from tickets"
        end)

      assert event_revenue_entry == nil

      # Should have donation revenue entry
      donation_revenue_entry =
        Enum.find(entries, fn e ->
          e.description =~ "Donation revenue from tickets" && e.debit_credit == :credit
        end)

      assert donation_revenue_entry != nil
      assert donation_revenue_entry.amount == donation_amount

      # Verify ledger balance
      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end

    test "process_event_payment_with_donations/1 handles event-only payments", %{user: user} do
      # $75.00 event only (no donations)
      total_amount = Money.new(7_500, :USD)
      event_amount = Money.new(7_500, :USD)
      donation_amount = Money.new(0, :USD)
      stripe_fee = Money.new(240, :USD)
      event_id = Ecto.ULID.generate()

      payment_attrs = %{
        user_id: user.id,
        total_amount: total_amount,
        event_amount: event_amount,
        donation_amount: donation_amount,
        event_id: event_id,
        external_payment_id: "pi_event_only_123",
        stripe_fee: stripe_fee,
        description: "Event tickets only - Order ORD789",
        payment_method_id: nil
      }

      assert {:ok, {payment, _transaction, entries}} =
               Ledgers.process_event_payment_with_donations(payment_attrs)

      # Check payment was created
      assert %Payment{} = payment
      assert payment.amount == total_amount

      # Check entries - should have event revenue entry
      event_revenue_entry =
        Enum.find(entries, fn e ->
          e.description =~ "Event revenue from tickets" && e.debit_credit == :credit
        end)

      assert event_revenue_entry != nil
      assert event_revenue_entry.amount == event_amount

      # Should NOT have donation revenue entry
      donation_revenue_entry =
        Enum.find(entries, fn e ->
          e.description =~ "Donation revenue from tickets"
        end)

      assert donation_revenue_entry == nil

      # Verify ledger balance
      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end

    test "process_event_payment_with_donations/1 creates correct account balances", %{user: user} do
      # $100.00 total: $60.00 event + $40.00 donation
      total_amount = Money.new(10_000, :USD)
      event_amount = Money.new(6_000, :USD)
      donation_amount = Money.new(4_000, :USD)
      stripe_fee = Money.new(320, :USD)
      event_id = Ecto.ULID.generate()

      payment_attrs = %{
        user_id: user.id,
        total_amount: total_amount,
        event_amount: event_amount,
        donation_amount: donation_amount,
        event_id: event_id,
        external_payment_id: "pi_balance_test_123",
        stripe_fee: stripe_fee,
        description: "Balance test - Order ORD999",
        payment_method_id: nil
      }

      assert {:ok, {_payment, _transaction, _entries}} =
               Ledgers.process_event_payment_with_donations(payment_attrs)

      # Check account balances
      event_revenue_account = Ledgers.get_account_by_name("event_revenue")
      donation_revenue_account = Ledgers.get_account_by_name("donation_revenue")
      stripe_account = Ledgers.get_account_by_name("stripe_account")
      stripe_fees_account = Ledgers.get_account_by_name("stripe_fees")

      event_balance = Ledgers.get_account_balance(event_revenue_account.id)
      donation_balance = Ledgers.get_account_balance(donation_revenue_account.id)
      stripe_balance = Ledgers.get_account_balance(stripe_account.id)
      fees_balance = Ledgers.get_account_balance(stripe_fees_account.id)

      # Event revenue should be credited (positive balance for credit-normal account)
      assert Money.equal?(event_balance, event_amount)

      # Donation revenue should be credited (positive balance for credit-normal account)
      assert Money.equal?(donation_balance, donation_amount)

      # Stripe account should have net receivable (total - fee)
      expected_stripe_balance = Money.sub(total_amount, stripe_fee) |> elem(1)
      assert Money.equal?(stripe_balance, expected_stripe_balance)

      # Stripe fees should be debited (positive balance for debit-normal account)
      assert Money.equal?(fees_balance, stripe_fee)
    end
  end

  describe "credit management" do
    setup do
      user = user_fixture()
      Ledgers.ensure_basic_accounts()

      # Configure QuickBooks client to use mock (prevents errors when sync jobs run)
      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      # Set up QuickBooks configuration for tests
      Application.put_env(:ysc, :quickbooks,
        client_id: "test_client_id",
        client_secret: "test_client_secret",
        company_id: "test_company_id",
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        event_item_id: "event_item_123",
        donation_item_id: "donation_item_123",
        bank_account_id: "bank_account_123",
        stripe_account_id: "stripe_account_123"
      )

      # Set up default mocks for automatic sync jobs
      import Mox

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_default", "TotalAmt" => "0.00"}}
      end)

      %{user: user}
    end

    test "add_credit/1 creates credit entries", %{user: user} do
      # $10.00
      credit_amount = Money.new(1000, :USD)

      credit_attrs = %{
        user_id: user.id,
        amount: credit_amount,
        reason: "Compensation for service issue",
        entity_type: :administration,
        entity_id: nil
      }

      assert {:ok, {credit_payment, transaction, entries}} = Ledgers.add_credit(credit_attrs)

      # Check credit payment was created
      assert %Payment{} = credit_payment
      assert credit_payment.amount == credit_amount
      assert credit_payment.user_id == user.id
      assert String.starts_with?(credit_payment.external_payment_id, "credit_")

      # Check transaction was created
      assert %LedgerTransaction{} = transaction
      assert transaction.type == :adjustment
      assert transaction.total_amount == credit_amount
      assert transaction.status == :completed

      # Check entries were created (should be 2: accounts receivable debit, cash credit)
      assert length(entries) == 2

      # Verify all entries have the correct payment_id
      Enum.each(entries, fn entry ->
        assert entry.payment_id == credit_payment.id
      end)
    end
  end
end
