defmodule Ysc.Quickbooks.SyncTest do
  @moduledoc """
  Tests for Quickbooks.Sync module.
  """
  use Ysc.DataCase, async: true

  import Mox
  import Ysc.AccountsFixtures

  alias Ysc.Quickbooks.Sync
  alias Ysc.Ledgers
  alias Ysc.Ledgers.{Payment, Refund, Payout}
  alias Ysc.Repo
  alias Ysc.Quickbooks.ClientMock

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Clear cache before each test to ensure mocks are used
    Cachex.clear(:ysc_cache)

    Ledgers.ensure_basic_accounts()
    user = user_fixture()

    # Configure the QuickBooks client to use the mock
    Application.put_env(:ysc, :quickbooks_client, ClientMock)

    # Set up QuickBooks configuration in application config for tests
    Application.put_env(:ysc, :quickbooks,
      client_id: "test_client_id",
      client_secret: "test_client_secret",
      company_id: "test_company_id",
      access_token: "test_access_token",
      refresh_token: "test_refresh_token",
      # Item IDs
      event_item_id: "event_item_123",
      donation_item_id: "donation_item_123",
      clear_lake_booking_item_id: "clear_lake_item_123",
      tahoe_booking_item_id: "tahoe_item_123",
      # Account IDs
      bank_account_id: "bank_account_123",
      stripe_account_id: "stripe_account_123"
    )

    %{user: user}
  end

  describe "sync_payment/1" do
    test "successfully syncs a payment", %{user: user} do
      # Setup mocks
      expect(ClientMock, :create_customer, fn _params ->
        {:ok, "qb_customer_123"}
      end)

      # Mock create_purchase_sales_receipt via Client module redirect if needed
      # Sync calls Quickbooks.create_purchase_sales_receipt which calls Client.create_sales_receipt
      expect(ClientMock, :create_sales_receipt, fn params ->
        assert params.customer_ref.value == "qb_customer_123"
        {:ok, %{"Id" => "qb_sales_receipt_123"}}
      end)

      # We also need query_class_by_name for the class lookup
      stub(ClientMock, :query_class_by_name, fn _name ->
        {:ok, "qb_class_123"}
      end)

      # Create a payment
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.create_payment(%{
          user_id: user.id,
          amount: Money.new(100, :USD),
          reference_id: "PMT-SYNC-TEST",
          payment_method: :stripe,
          payment_date: DateTime.utc_now()
        })

      # Run sync
      assert {:ok, result} = Sync.sync_payment(payment)
      assert result["Id"] == "qb_sales_receipt_123"

      # Verify payment updated
      updated_payment = Repo.get(Payment, payment.id)
      assert updated_payment.quickbooks_sync_status == "synced"
      assert updated_payment.quickbooks_sales_receipt_id == "qb_sales_receipt_123"
    end

    test "handles sync failure", %{user: user} do
      # Setup mocks to fail
      expect(ClientMock, :create_customer, fn _params ->
        {:ok, "qb_customer_123"}
      end)

      expect(ClientMock, :create_sales_receipt, fn _params ->
        {:error, "API Error"}
      end)

      stub(ClientMock, :query_class_by_name, fn _name ->
        {:ok, "qb_class_123"}
      end)

      # Create a payment
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.create_payment(%{
          user_id: user.id,
          amount: Money.new(100, :USD),
          reference_id: "PMT-FAIL-TEST",
          payment_method: :stripe,
          payment_date: DateTime.utc_now()
        })

      # Run sync
      assert {:error, "API Error"} = Sync.sync_payment(payment)

      # Verify payment updated with error
      updated_payment = Repo.get(Payment, payment.id)
      assert updated_payment.quickbooks_sync_status == "failed"
      assert updated_payment.quickbooks_sync_error["error"] =~ "API Error"
    end
  end

  describe "sync_refund/1" do
    test "successfully syncs a refund", %{user: user} do
      # Setup mocks
      expect(ClientMock, :create_customer, fn _params ->
        {:ok, "qb_customer_123"}
      end)

      # Mock create_refund_receipt
      expect(ClientMock, :create_refund_receipt, fn params ->
        assert params.customer_ref.value == "qb_customer_123"
        {:ok, %{"Id" => "qb_refund_receipt_123"}}
      end)

      stub(ClientMock, :query_class_by_name, fn _name ->
        {:ok, "qb_class_123"}
      end)

      stub(ClientMock, :query_account_by_name, fn _name ->
        {:ok, "qb_undeposited_funds_123"}
      end)

      # Create a payment first
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.create_payment(%{
          user_id: user.id,
          amount: Money.new(100, :USD),
          reference_id: "PMT-REFUND-TEST",
          payment_method: :stripe,
          payment_date: DateTime.utc_now()
        })

      # Create a refund
      {:ok, {refund, _transaction, _entries}} =
        Ledgers.create_refund(%{
          payment_id: payment.id,
          user_id: user.id,
          amount: Money.new(50, :USD),
          reference_id: "RFD-SYNC-TEST",
          reason: "Test Refund"
        })

      # Run sync
      assert {:ok, result} = Sync.sync_refund(refund)
      assert result["Id"] == "qb_refund_receipt_123"

      # Verify refund updated
      updated_refund = Repo.get(Refund, refund.id)
      assert updated_refund.quickbooks_sync_status == "synced"
      assert updated_refund.quickbooks_sales_receipt_id == "qb_refund_receipt_123"
    end
  end

  describe "sync_payout/1" do
    test "successfully syncs a payout", %{user: user} do
      # Setup mocks
      expect(ClientMock, :create_deposit, fn _params ->
        {:ok, %{"Id" => "qb_deposit_123"}}
      end)

      stub(ClientMock, :query_class_by_name, fn _name ->
        {:ok, "qb_class_123"}
      end)

      # Create a payment
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.create_payment(%{
          user_id: user.id,
          amount: Money.new(100, :USD),
          reference_id: "PMT-PAYOUT-TEST",
          payment_method: :stripe,
          payment_date: DateTime.utc_now()
        })

      # Mark payment as synced so it's included in payout sync
      payment
      |> Payment.changeset(%{
        quickbooks_sync_status: "synced",
        quickbooks_sales_receipt_id: "qb_sr_123"
      })
      |> Repo.update!()

      # Create a payout
      {:ok, {_payout_payment, _transaction, _entries, payout}} =
        Ledgers.process_stripe_payout(%{
          payout_amount: Money.new(100, :USD),
          stripe_payout_id: "po_sync_test",
          description: "Test Payout",
          currency: "usd",
          status: "paid",
          arrival_date: DateTime.utc_now(),
          metadata: %{}
        })

      # Link payment to payout
      {:ok, payout} = Ledgers.link_payment_to_payout(payout, payment)

      # Run sync
      assert {:ok, result} = Sync.sync_payout(payout)
      assert result["Id"] == "qb_deposit_123"

      # Verify payout updated
      updated_payout = Repo.get(Payout, payout.id)
      assert updated_payout.quickbooks_sync_status == "synced"
      assert updated_payout.quickbooks_deposit_id == "qb_deposit_123"
    end
  end
end
