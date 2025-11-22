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
        realm_id: "test_realm_id",
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
        realm_id: "test_realm_id",
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
      # May also have revenue reversal debit if revenue entry found
      assert length(entries) >= 2
      assert length(entries) <= 3

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
        realm_id: "test_realm_id",
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
