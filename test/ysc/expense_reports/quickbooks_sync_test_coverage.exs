defmodule Ysc.ExpenseReports.QuickbooksSyncTest do
  @moduledoc """
  Tests for Ysc.ExpenseReports.QuickbooksSync.
  """
  use Ysc.DataCase, async: true

  import Mox
  import Ysc.AccountsFixtures

  alias Ysc.ExpenseReports.QuickbooksSync
  alias Ysc.ExpenseReports.ExpenseReport
  alias Ysc.Repo
  alias Ysc.Quickbooks.ClientMock

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    Cachex.clear(:ysc_cache)
    user = user_fixture()

    Application.put_env(:ysc, :quickbooks_client, ClientMock)

    # Set up config for accounts
    Application.put_env(:ysc, :quickbooks,
      default_expense_account_id: "qb_expense_acct_123",
      ap_account_id: "qb_ap_acct_123",
      default_income_account_id: "qb_income_acct_123"
    )

    %{user: user}
  end

  describe "sync_expense_report/1" do
    test "successfully syncs an expense report", %{user: user} do
      # Setup mocks
      expect(ClientMock, :get_or_create_vendor, fn _name, _params ->
        {:ok, "qb_vendor_123"}
      end)

      expect(ClientMock, :create_bill, fn _params, _opts ->
        {:ok, %{"Id" => "qb_bill_123"}}
      end)

      # Create expense report
      {:ok, expense_report} =
        %ExpenseReport{
          user_id: user.id,
          status: "approved",
          purpose: "Test Report",
          reimbursement_method: "bank_transfer",
          expense_items: [
            %Ysc.ExpenseReports.ExpenseReportItem{
              date: Date.utc_today(),
              description: "Item 1",
              amount: Money.new(1000, :USD),
              vendor: "Vendor 1"
            }
          ],
          income_items: []
        }
        |> Repo.insert()

      # Preload associations as expected by sync function
      expense_report =
        Repo.preload(expense_report, [
          :expense_items,
          :income_items,
          :address,
          :bank_account,
          :event,
          :user
        ])

      assert {:ok, result} = QuickbooksSync.sync_expense_report(expense_report)
      assert result["Id"] == "qb_bill_123"

      # Verify update
      updated_report = Repo.get(ExpenseReport, expense_report.id)
      assert updated_report.quickbooks_sync_status == "synced"
      assert updated_report.quickbooks_bill_id == "qb_bill_123"
      assert updated_report.quickbooks_vendor_id == "qb_vendor_123"
    end

    test "handles sync failure", %{user: user} do
      expect(ClientMock, :get_or_create_vendor, fn _name, _params ->
        {:ok, "qb_vendor_123"}
      end)

      expect(ClientMock, :create_bill, fn _params, _opts ->
        {:error, "API Error"}
      end)

      {:ok, expense_report} =
        %ExpenseReport{
          user_id: user.id,
          status: "approved",
          purpose: "Test Fail",
          reimbursement_method: "bank_transfer",
          expense_items: [],
          income_items: []
        }
        |> Repo.insert()

      expense_report =
        Repo.preload(expense_report, [
          :expense_items,
          :income_items,
          :address,
          :bank_account,
          :event,
          :user
        ])

      assert {:error, "API Error"} = QuickbooksSync.sync_expense_report(expense_report)

      updated_report = Repo.get(ExpenseReport, expense_report.id)
      assert updated_report.quickbooks_sync_status == "failed"
      assert updated_report.quickbooks_sync_error =~ "API Error"
    end

    test "skips creation if already has bill_id", %{user: user} do
      {:ok, expense_report} =
        %ExpenseReport{
          user_id: user.id,
          status: "approved",
          purpose: "Already Synced",
          reimbursement_method: "bank_transfer",
          quickbooks_bill_id: "qb_bill_existing",
          quickbooks_sync_status: "synced",
          expense_items: [],
          income_items: []
        }
        |> Repo.insert()

      # No mocks expected because it should return early

      assert {:ok, result} = QuickbooksSync.sync_expense_report(expense_report)
      assert result["Id"] == "qb_bill_existing"
    end
  end
end
