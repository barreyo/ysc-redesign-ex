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
      assert accounts_with_balances != []

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

  describe "payout processing" do
    setup do
      user = user_fixture()
      Ledgers.ensure_basic_accounts()

      # Configure QuickBooks client to use mock
      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

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

      # Create test payments
      {:ok, {payment1, _transaction1, _entries1}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :event,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_payout_1",
          stripe_fee: Money.new(320, :USD),
          description: "Payment 1",
          property: nil,
          payment_method_id: nil
        })

      {:ok, {payment2, _transaction2, _entries2}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(5_000, :USD),
          entity_type: :event,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_payout_2",
          stripe_fee: Money.new(160, :USD),
          description: "Payment 2",
          property: nil,
          payment_method_id: nil
        })

      %{user: user, payment1: payment1, payment2: payment2}
    end

    test "process_stripe_payout/1 creates payout with entries", %{payment1: _payment1} do
      payout_attrs = %{
        payout_amount: Money.new(10_000, :USD),
        stripe_payout_id: "po_test_123",
        description: "Test payout",
        currency: "usd",
        status: "paid",
        arrival_date: DateTime.utc_now(),
        metadata: %{}
      }

      assert {:ok, {payout_payment, transaction, entries, payout}} =
               Ledgers.process_stripe_payout(payout_attrs)

      assert payout_payment.amount == Money.new(10_000, :USD)
      assert payout.stripe_payout_id == "po_test_123"
      assert transaction.type == :payout
      assert length(entries) >= 2
    end

    test "link_payment_to_payout/2 links payment to payout", %{
      payment1: payment1,
      payment2: payment2
    } do
      {:ok, {_payout_payment, _transaction, _entries, payout}} =
        Ledgers.process_stripe_payout(%{
          payout_amount: Money.new(15_000, :USD),
          stripe_payout_id: "po_link_test",
          description: "Test payout",
          currency: "usd",
          status: "paid",
          arrival_date: DateTime.utc_now(),
          metadata: %{}
        })

      assert {:ok, updated_payout} = Ledgers.link_payment_to_payout(payout, payment1)
      assert {:ok, updated_payout} = Ledgers.link_payment_to_payout(updated_payout, payment2)

      # Reload payout with payments
      updated_payout = Ysc.Repo.reload!(updated_payout) |> Ysc.Repo.preload(:payments)
      assert length(updated_payout.payments) == 2
    end

    test "link_refund_to_payout/2 links refund to payout", %{payment1: payment1} do
      {:ok, {refund, _transaction, _entries}} =
        Ledgers.process_refund(%{
          payment_id: payment1.id,
          refund_amount: Money.new(2_000, :USD),
          external_refund_id: "re_payout_test",
          reason: "Test refund"
        })

      {:ok, {_payout_payment, _transaction, _entries, payout}} =
        Ledgers.process_stripe_payout(%{
          payout_amount: Money.new(8_000, :USD),
          stripe_payout_id: "po_refund_link_test",
          description: "Test payout",
          currency: "usd",
          status: "paid",
          arrival_date: DateTime.utc_now(),
          metadata: %{}
        })

      assert {:ok, updated_payout} = Ledgers.link_refund_to_payout(payout, refund)

      # Reload payout with refunds
      updated_payout = Ysc.Repo.reload!(updated_payout) |> Ysc.Repo.preload(:refunds)
      assert length(updated_payout.refunds) == 1
    end
  end

  describe "balance calculations" do
    setup do
      user = user_fixture()
      Ledgers.ensure_basic_accounts()

      # Configure QuickBooks client to use mock
      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

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

    test "verify_ledger_balance/0 returns balanced for empty ledger" do
      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end

    test "verify_ledger_balance/0 returns balanced after payment", %{user: user} do
      {:ok, {_payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_balance_test",
          stripe_fee: Money.new(320, :USD),
          description: "Test payment",
          property: nil,
          payment_method_id: nil
        })

      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end

    test "verify_ledger_balance/0 returns balanced after payment and refund", %{user: user} do
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_balance_refund_test",
          stripe_fee: Money.new(320, :USD),
          description: "Test payment",
          property: nil,
          payment_method_id: nil
        })

      {:ok, {_refund, _refund_transaction, _refund_entries}} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: Money.new(5_000, :USD),
          external_refund_id: "re_balance_test",
          reason: "Test refund"
        })

      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end

    test "get_account_balance/2 respects date range", %{user: user} do
      # Membership payments create entries for stripe_account (debit) and membership_revenue (credit)
      # Check stripe_account which should have a positive balance
      account = Ledgers.get_account_by_name("stripe_account")

      # Get today's date range first
      today = Date.utc_today()
      today_start = DateTime.new!(today, ~T[00:00:00], "Etc/UTC")
      today_end = DateTime.new!(today, ~T[23:59:59], "Etc/UTC")

      # Create payment with unique external_payment_id
      unique_id = "pi_date_range_test_#{System.unique_integer([:positive])}"

      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: unique_id,
          stripe_fee: Money.new(320, :USD),
          description: "Test payment",
          property: nil,
          payment_method_id: nil
        })

      # Update payment_date using direct SQL to ensure it's within today's range
      Ysc.Repo.update_all(
        from(p in Ysc.Ledgers.Payment, where: p.id == ^payment.id),
        set: [payment_date: today_start]
      )

      balance_today = Ledgers.get_account_balance(account.id, today_start, today_end)
      assert Money.positive?(balance_today)

      # Get balance for yesterday (should be zero)
      yesterday = Date.add(today, -1)
      yesterday_start = DateTime.new!(yesterday, ~T[00:00:00], "Etc/UTC")
      yesterday_end = DateTime.new!(yesterday, ~T[23:59:59], "Etc/UTC")
      balance_yesterday = Ledgers.get_account_balance(account.id, yesterday_start, yesterday_end)
      assert Money.equal?(balance_yesterday, Money.new(0, :USD))
    end
  end

  describe "payment types" do
    setup do
      user = user_fixture()
      Ledgers.ensure_basic_accounts()

      # Configure QuickBooks client to use mock
      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

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

    test "process_payment/1 handles booking payments", %{user: user} do
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(20_000, :USD),
          entity_type: :booking,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_booking_test",
          stripe_fee: Money.new(640, :USD),
          description: "Tahoe booking",
          property: :tahoe,
          payment_method_id: nil
        })

      # entity_type is stored in ledger entries, not on payment directly
      entries = Ysc.Ledgers.get_entries_by_payment(payment.id)
      booking_entry = Enum.find(entries, &(&1.related_entity_type == :booking))
      assert booking_entry.related_entity_type == :booking
      # Property is used to determine revenue account but not stored in ledger entries
      # Verify the description contains the property information
      assert booking_entry.description =~ "Tahoe"
      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end

    test "process_payment/1 handles subscription payments", %{user: user} do
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(15_000, :USD),
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_subscription_test",
          stripe_fee: Money.new(480, :USD),
          description: "Membership subscription",
          property: nil,
          payment_method_id: nil
        })

      # entity_type is stored in ledger entries, not on payment directly
      # Subscription payments use :membership as entity_type
      entries = Ysc.Ledgers.get_entries_by_payment(payment.id)
      membership_entry = Enum.find(entries, &(&1.related_entity_type == :membership))
      assert membership_entry.related_entity_type == :membership
      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end

    test "process_payment/1 handles donation payments", %{user: user} do
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(5_000, :USD),
          entity_type: :donation,
          entity_id: Ecto.ULID.generate(),
          external_payment_id: "pi_donation_test",
          stripe_fee: Money.new(160, :USD),
          description: "Donation",
          property: nil,
          payment_method_id: nil
        })

      # entity_type is stored in ledger entries, not on payment directly
      entries = Ysc.Ledgers.get_entries_by_payment(payment.id)
      donation_entry = Enum.find(entries, &(&1.related_entity_type == :donation))
      assert donation_entry.related_entity_type == :donation
      assert {:ok, :balanced} = Ledgers.verify_ledger_balance()
    end
  end
end
