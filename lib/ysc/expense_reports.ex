defmodule Ysc.ExpenseReports do
  @moduledoc """
  Context module for managing expense reports.
  """
  require Logger
  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.Accounts.User

  alias Ysc.ExpenseReports.{
    ExpenseReport,
    ExpenseReportItem,
    ExpenseReportIncomeItem,
    BankAccount
  }

  alias Ysc.S3Config

  # Expense Reports

  def list_expense_reports(%User{} = user) do
    Repo.all(
      from er in ExpenseReport,
        where: er.user_id == ^user.id,
        order_by: [desc: :inserted_at],
        preload: [:expense_items, :income_items, :address]
    )
    |> Enum.map(fn report ->
      # Load bank_account separately without accessing encrypted fields
      bank_account =
        if report.bank_account_id do
          Repo.get(BankAccount, report.bank_account_id)
        else
          nil
        end

      %{report | bank_account: bank_account}
    end)
  end

  def get_expense_report!(id, %User{} = user) do
    report =
      Repo.one!(
        from er in ExpenseReport,
          where: er.id == ^id and er.user_id == ^user.id,
          preload: [:expense_items, :income_items, :address]
      )

    # Load bank_account separately without accessing encrypted fields
    bank_account =
      if report.bank_account_id do
        Repo.get(BankAccount, report.bank_account_id)
      else
        nil
      end

    %{report | bank_account: bank_account}
  end

  def create_expense_report(attrs, %User{} = user) do
    require Logger

    # Set status to "submitted" if not already set (for submissions)
    attrs = Map.put_new(attrs, "status", "submitted")

    changeset =
      %ExpenseReport{}
      |> ExpenseReport.changeset(
        Map.put(attrs, "user_id", user.id),
        validate_address_ownership: true,
        validate_bank_account_ownership: true
      )
      |> validate_reimbursement_setup(user)
      |> validate_all_expense_items_have_receipts_for_submission()

    Logger.debug(
      "Expense report changeset - valid?: #{changeset.valid?}, errors: #{inspect(changeset.errors, limit: 20)}"
    )

    # Check for nested association errors
    expense_items = Ecto.Changeset.get_field(changeset, :expense_items, [])
    Logger.debug("Expense items count: #{length(expense_items)}")

    Enum.with_index(expense_items)
    |> Enum.each(fn {item, idx} ->
      case item do
        %Ecto.Changeset{} = cs ->
          receipt_path = Ecto.Changeset.get_field(cs, :receipt_s3_path)

          Logger.debug(
            "Expense item #{idx} - valid?: #{cs.valid?}, errors: #{inspect(cs.errors, limit: 10)}, receipt: #{inspect(receipt_path)}"
          )

        struct ->
          receipt_path = Map.get(struct, :receipt_s3_path)
          Logger.debug("Expense item #{idx} - struct, receipt: #{inspect(receipt_path)}")
      end
    end)

    # Also check if there are changeset errors in the associations
    if Map.has_key?(changeset.changes, :expense_items) do
      Logger.debug("expense_items in changes - checking for errors")

      case changeset.changes[:expense_items] do
        list when is_list(list) ->
          Enum.with_index(list)
          |> Enum.each(fn {item, idx} ->
            case item do
              %Ecto.Changeset{} = cs ->
                Logger.debug(
                  "Changed expense item #{idx} - valid?: #{cs.valid?}, errors: #{inspect(cs.errors, limit: 10)}"
                )

              _ ->
                :ok
            end
          end)

        _ ->
          :ok
      end
    end

    result = Repo.insert(changeset)

    # Enqueue QuickBooks sync job if expense report was created with "submitted" status
    case result do
      {:ok, expense_report} ->
        if expense_report.status == "submitted" do
          Logger.debug("Expense report created with submitted status, enqueueing QuickBooks sync",
            expense_report_id: expense_report.id
          )

          enqueue_quickbooks_sync(expense_report)
        else
          Logger.debug(
            "Expense report created with status: #{expense_report.status}, skipping QuickBooks sync",
            expense_report_id: expense_report.id
          )
        end

        result

      error ->
        error
    end
  end

  defp validate_all_expense_items_have_receipts_for_submission(changeset) do
    # Only validate if status is "submitted"
    status = Ecto.Changeset.get_field(changeset, :status)

    if status == "submitted" do
      expense_items = Ecto.Changeset.get_field(changeset, :expense_items, [])

      items_without_receipts =
        expense_items
        |> Enum.filter(fn item ->
          receipt_path = get_receipt_path_from_item(item)
          is_nil(receipt_path) || receipt_path == ""
        end)

      if Enum.any?(items_without_receipts) do
        Ecto.Changeset.add_error(
          changeset,
          :expense_items,
          "All expense items must have a receipt attached before submission"
        )
      else
        changeset
      end
    else
      changeset
    end
  end

  defp get_receipt_path_from_item(%Ecto.Changeset{} = item) do
    Ecto.Changeset.get_field(item, :receipt_s3_path)
  end

  defp get_receipt_path_from_item(%ExpenseReportItem{} = item) do
    item.receipt_s3_path
  end

  defp get_receipt_path_from_item(_), do: nil

  defp validate_reimbursement_setup(changeset, %User{} = user) do
    method = Ecto.Changeset.get_field(changeset, :reimbursement_method)

    case method do
      "bank_transfer" ->
        bank_account_id = Ecto.Changeset.get_field(changeset, :bank_account_id)

        if is_nil(bank_account_id) do
          # Check if user has any bank accounts
          bank_accounts = list_bank_accounts(user)

          if length(bank_accounts) == 0 do
            Ecto.Changeset.add_error(
              changeset,
              :reimbursement_method,
              "requires a bank account. Please add a bank account in your user settings before submitting."
            )
          else
            Ecto.Changeset.add_error(
              changeset,
              :bank_account_id,
              "must be selected. Please choose a bank account above."
            )
          end
        else
          changeset
        end

      "check" ->
        address_id = Ecto.Changeset.get_field(changeset, :address_id)
        billing_address = Ysc.Accounts.get_billing_address(user)

        if is_nil(address_id) do
          if is_nil(billing_address) do
            Ecto.Changeset.add_error(
              changeset,
              :reimbursement_method,
              "requires a billing address. Please add an address in your user settings before submitting."
            )
          else
            # Auto-set the billing address if available
            Ecto.Changeset.put_change(changeset, :address_id, billing_address.id)
          end
        else
          changeset
        end

      _ ->
        changeset
    end
  end

  def update_expense_report(%ExpenseReport{} = expense_report, attrs) do
    expense_report
    |> ExpenseReport.changeset(attrs)
    |> Repo.update()
  end

  def submit_expense_report(%ExpenseReport{} = expense_report) do
    result =
      expense_report
      |> ExpenseReport.changeset(%{status: "submitted"})
      |> Repo.update()

    # Enqueue QuickBooks sync job if submission was successful
    case result do
      {:ok, updated_report} ->
        enqueue_quickbooks_sync(updated_report)
        result

      error ->
        error
    end
  end

  defp enqueue_quickbooks_sync(%ExpenseReport{} = expense_report) do
    Logger.debug("Starting enqueue_quickbooks_sync",
      expense_report_id: expense_report.id,
      current_status: expense_report.quickbooks_sync_status
    )

    # Mark as pending sync
    update_result =
      expense_report
      |> ExpenseReport.changeset(%{quickbooks_sync_status: "pending"})
      |> Repo.update()

    case update_result do
      {:ok, updated_report} ->
        Logger.debug("Marked expense report as pending sync",
          expense_report_id: updated_report.id
        )

        # Enqueue Oban job
        job_result =
          %{"expense_report_id" => expense_report.id}
          |> YscWeb.Workers.QuickbooksSyncExpenseReportWorker.new()
          |> Oban.insert()

        case job_result do
          {:ok, job} ->
            Logger.info("Enqueued QuickBooks sync for expense report",
              expense_report_id: expense_report.id,
              job_id: job.id,
              queue: job.queue,
              scheduled_at: job.scheduled_at
            )

          {:error, reason} ->
            Logger.error("Failed to enqueue QuickBooks sync for expense report",
              expense_report_id: expense_report.id,
              error: inspect(reason)
            )

            Sentry.capture_message("Failed to enqueue QuickBooks sync for expense report",
              level: :error,
              extra: %{
                expense_report_id: expense_report.id,
                error: inspect(reason)
              },
              tags: %{
                quickbooks_operation: "enqueue_expense_report_sync"
              }
            )
        end

      {:error, changeset} ->
        Logger.error("Failed to mark expense report as pending sync",
          expense_report_id: expense_report.id,
          errors: inspect(changeset.errors)
        )
    end
  end

  def delete_expense_report(%ExpenseReport{} = expense_report) do
    Repo.delete(expense_report)
  end

  # Bank Accounts

  @doc """
  Lists bank accounts for a user. Returns structs with encrypted fields.

  **IMPORTANT**: The encrypted fields (account_number, routing_number) are stored encrypted
  and will only be decrypted if you access them directly. This function returns structs
  that have NOT been decrypted. Only access `.account_number_last_4` from these structs.

  Use `get_decrypted_bank_account/2` if you need the actual decrypted account/routing numbers.
  """
  def list_bank_accounts(%User{} = user) do
    Repo.all(
      from ba in BankAccount,
        where: ba.user_id == ^user.id,
        order_by: [desc: :inserted_at]
    )
  end

  @doc """
  Gets a bank account by ID. Returns struct with encrypted fields.
  The encrypted fields are NOT automatically decrypted.
  Use `get_decrypted_bank_account/2` if you need the decrypted values.
  """
  def get_bank_account!(id, %User{} = user) do
    Repo.one!(
      from ba in BankAccount,
        where: ba.id == ^id and ba.user_id == ^user.id
    )
  end

  @doc """
  Gets a bank account by ID. Returns struct with encrypted fields.
  The encrypted fields are NOT automatically decrypted.
  Use `get_decrypted_bank_account/2` if you need the decrypted values.
  """
  def get_bank_account(id, %User{} = user) do
    Repo.one(
      from ba in BankAccount,
        where: ba.id == ^id and ba.user_id == ^user.id
    )
  end

  @doc """
  Gets a bank account with decrypted account and routing numbers.
  Use this ONLY when you need the actual decrypted values (e.g., for processing payments).
  """
  def get_decrypted_bank_account(id, %User{} = user) do
    case get_bank_account(id, user) do
      nil -> nil
      bank_account -> BankAccount.get_decrypted_details(bank_account)
    end
  end

  @doc """
  Gets a bank account with decrypted account and routing numbers (raises if not found).
  Use this ONLY when you need the actual decrypted values (e.g., for processing payments).
  """
  def get_decrypted_bank_account!(id, %User{} = user) do
    bank_account = get_bank_account!(id, user)
    BankAccount.get_decrypted_details(bank_account)
  end

  def create_bank_account(attrs, %User{} = user) do
    %BankAccount{}
    |> BankAccount.changeset(Map.put(attrs, "user_id", user.id))
    |> Repo.insert()
  end

  def update_bank_account(%BankAccount{} = bank_account, attrs) do
    bank_account
    |> BankAccount.changeset(attrs)
    |> Repo.update()
  end

  def delete_bank_account(%BankAccount{} = bank_account) do
    Repo.delete(bank_account)
  end

  # Calculations

  def calculate_totals(%ExpenseReport{} = expense_report) do
    expense_total =
      case Repo.one(
             from ei in ExpenseReportItem,
               where: ei.expense_report_id == ^expense_report.id,
               select: sum(fragment("(?.amount).amount", ei))
           ) do
        nil -> Money.new(0, :USD)
        amount -> Money.new(amount, :USD)
      end

    income_total =
      case Repo.one(
             from ii in ExpenseReportIncomeItem,
               where: ii.expense_report_id == ^expense_report.id,
               select: sum(fragment("(?.amount).amount", ii))
           ) do
        nil -> Money.new(0, :USD)
        amount -> Money.new(amount, :USD)
      end

    net_total =
      case Money.sub(expense_total, income_total) do
        {:ok, result} -> result
        _ -> Money.new(0, :USD)
      end

    %{
      expense_total: expense_total,
      income_total: income_total,
      net_total: net_total
    }
  end

  # S3 Upload for Expense Reports
  #
  # IMPORTANT: The expense-reports bucket is BACKEND-ONLY.
  # - Files are uploaded to the LiveView server first (via allow_upload)
  # - The backend then uploads to S3 using ExAws with backend credentials
  # - The bucket has NO CORS configuration, preventing direct frontend access
  # - All access uses AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY from environment

  @doc """
  Uploads a file directly to S3 in the expense reports bucket.
  This function is called by the backend after receiving the file from the LiveView upload.
  Returns the S3 path (key) for the uploaded file.

  Uses backend credentials configured via ExAws (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY).
  """
  def upload_receipt_to_s3(path) do
    require Logger
    file_name = Path.basename(path)
    # Generate a unique key with timestamp to avoid collisions
    timestamp = System.system_time(:second)
    unique_key = "receipts/#{timestamp}_#{file_name}"
    bucket_name = S3Config.expense_reports_bucket_name()

    Logger.debug("Uploading receipt to S3", path: path, bucket: bucket_name, key: unique_key)

    result =
      path
      |> ExAws.S3.Upload.stream_file()
      |> ExAws.S3.upload(bucket_name, unique_key)
      |> ExAws.request!()

    Logger.debug("S3 upload result", result: inspect(result, limit: 10))

    # Return the S3 path (key) - the full URL can be constructed using S3Config.object_url/2
    key = result[:body][:key] || unique_key
    Logger.debug("Returning S3 key", key: key)
    key
  end

  @doc """
  Constructs the full URL for an expense report receipt/proof stored in S3.
  """
  def receipt_url(s3_path) when is_binary(s3_path) do
    S3Config.object_url(s3_path, S3Config.expense_reports_bucket_name())
  end

  def receipt_url(_), do: nil
end
