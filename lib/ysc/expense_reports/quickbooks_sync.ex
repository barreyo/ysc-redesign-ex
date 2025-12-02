defmodule Ysc.ExpenseReports.QuickbooksSync do
  @moduledoc """
  Handles syncing ExpenseReport records to QuickBooks as Bills.

  This module provides functions to sync expense reports to QuickBooks Online,
  creating vendors, bills, and uploading receipts.
  """

  require Logger
  alias Ysc.Repo
  alias Ysc.ExpenseReports.ExpenseReport
  alias Ysc.Accounts.User
  alias Ysc.S3Config

  # Helper to get the configured QuickBooks client module (for testing with mocks)
  defp client_module do
    Application.get_env(:ysc, :quickbooks_client, Ysc.Quickbooks.Client)
  end

  @doc """
  Syncs an expense report to QuickBooks as a Bill.

  Returns {:ok, bill} on success, {:error, reason} on failure.
  """
  @spec sync_expense_report(ExpenseReport.t()) :: {:ok, map()} | {:error, atom() | String.t()}
  def sync_expense_report(%ExpenseReport{} = expense_report) do
    Logger.info("[QB Expense Sync] Starting sync for expense report",
      expense_report_id: expense_report.id,
      sync_status: expense_report.quickbooks_sync_status,
      bill_id: expense_report.quickbooks_bill_id
    )

    # Check if already synced
    if expense_report.quickbooks_sync_status == "synced" && expense_report.quickbooks_bill_id do
      Logger.info("[QB Expense Sync] Expense report already synced to QuickBooks",
        expense_report_id: expense_report.id,
        bill_id: expense_report.quickbooks_bill_id
      )

      {:ok, %{"Id" => expense_report.quickbooks_bill_id}}
    else
      # Update last sync attempt timestamp
      update_sync_attempt_timestamp(expense_report)

      # Ensure associations are loaded (they should already be preloaded by the worker)
      expense_report =
        if Ecto.assoc_loaded?(expense_report.user) &&
             Ecto.assoc_loaded?(expense_report.expense_items) do
          Logger.debug("[QB Expense Sync] Associations already loaded",
            expense_report_id: expense_report.id
          )

          expense_report
        else
          Logger.debug("[QB Expense Sync] Associations not loaded, preloading now",
            expense_report_id: expense_report.id,
            user_loaded: Ecto.assoc_loaded?(expense_report.user),
            expense_items_loaded: Ecto.assoc_loaded?(expense_report.expense_items)
          )

          expense_report
          |> Repo.preload([:expense_items, :income_items, :address, :bank_account])
          |> Repo.preload(user: :billing_address)
        end

      with {:ok, vendor_id} <- get_or_create_vendor(expense_report.user),
           {:ok, bill} <- create_bill(expense_report, vendor_id),
           {:ok, _} <- upload_and_link_receipts(expense_report, bill["Id"]) do
        # Update expense report with QuickBooks IDs
        update_expense_report_success(expense_report, vendor_id, bill["Id"])

        Logger.info("[QB Expense Sync] Successfully synced expense report to QuickBooks",
          expense_report_id: expense_report.id,
          bill_id: bill["Id"]
        )

        {:ok, bill}
      else
        {:error, reason} = error ->
          update_expense_report_error(expense_report, reason)

          Logger.error("[QB Expense Sync] Failed to sync expense report to QuickBooks",
            expense_report_id: expense_report.id,
            error: inspect(reason)
          )

          # Report to Sentry
          Sentry.capture_message("QuickBooks expense report sync failed",
            level: :error,
            extra: %{
              expense_report_id: expense_report.id,
              error: inspect(reason)
            },
            tags: %{
              quickbooks_operation: "sync_expense_report",
              expense_report_id: expense_report.id
            }
          )

          error
      end
    end
  end

  defp get_or_create_vendor(%User{} = user) do
    # Handle nil first_name or last_name
    first_name = user.first_name || ""
    last_name = user.last_name || ""
    display_name = String.trim("#{first_name} #{last_name}")

    # Fallback to email if name is empty
    display_name =
      if display_name == "" do
        user.email || "User #{user.id}"
      else
        display_name
      end

    Logger.debug("[QB Expense Sync] get_or_create_vendor: Getting or creating vendor",
      display_name: display_name,
      user_id: user.id,
      first_name: first_name,
      last_name: last_name,
      email: user.email
    )

    vendor_params = %{
      given_name: first_name,
      family_name: last_name,
      email: user.email
    }

    # Add billing address if available and loaded
    vendor_params =
      if Ecto.assoc_loaded?(user.billing_address) do
        case user.billing_address do
          nil ->
            Logger.debug("[QB Expense Sync] get_or_create_vendor: Billing address is nil")
            vendor_params

          billing_address ->
            Map.put(vendor_params, :bill_address, %{
              line1: billing_address.address,
              city: billing_address.city,
              country_sub_division_code: billing_address.region,
              postal_code: billing_address.postal_code,
              country: billing_address.country || "USA"
            })
        end
      else
        Logger.debug("[QB Expense Sync] get_or_create_vendor: Billing address not loaded")
        vendor_params
      end

    Logger.debug("[QB Expense Sync] get_or_create_vendor: Calling QuickBooks client",
      display_name: display_name,
      vendor_params: Map.keys(vendor_params)
    )

    result = client_module().get_or_create_vendor(display_name, vendor_params)

    case result do
      {:ok, vendor_id} ->
        Logger.info("[QB Expense Sync] get_or_create_vendor: Vendor obtained",
          vendor_id: vendor_id,
          display_name: display_name
        )

        {:ok, vendor_id}

      {:error, reason} ->
        Logger.error("[QB Expense Sync] get_or_create_vendor: Failed to get or create vendor",
          display_name: display_name,
          error: inspect(reason),
          error_type: if(is_atom(reason), do: reason, else: :unknown)
        )

        {:error, reason}

      other ->
        Logger.error("[QB Expense Sync] get_or_create_vendor: Unexpected result",
          display_name: display_name,
          result: inspect(other)
        )

        {:error, :unexpected_result}
    end
  end

  defp create_bill(%ExpenseReport{} = expense_report, vendor_id) do
    Logger.debug("[QB Expense Sync] create_bill: Creating bill",
      expense_report_id: expense_report.id,
      vendor_id: vendor_id
    )

    # Get default expense account (uncategorized expense) for line items
    # The treasurer will update this with proper accounts/classes later
    default_expense_account_id =
      case Application.get_env(:ysc, :quickbooks, [])[:default_expense_account_id] do
        nil ->
          # Try to query for "Uncategorized Expense" account
          case client_module().query_account_by_name("Uncategorized Expense") do
            {:ok, account_id} -> account_id
            _ -> nil
          end

        account_id ->
          account_id
      end

    if is_nil(default_expense_account_id) do
      Logger.warning("[QB Expense Sync] create_bill: No default expense account configured")
    end

    # Get Accounts Payable account (separate from expense account)
    ap_account_id =
      case Application.get_env(:ysc, :quickbooks, [])[:ap_account_id] do
        nil ->
          # Try to query for "Accounts Payable" account
          case client_module().query_account_by_name("Accounts Payable") do
            {:ok, account_id} -> account_id
            _ -> nil
          end

        account_id ->
          account_id
      end

    if is_nil(ap_account_id) do
      Logger.warning("[QB Expense Sync] create_bill: No Accounts Payable account configured")
    end

    # Build bill lines from expense items
    # Note: Currently using simple approach - default expense account for all items
    # The treasurer will update accounts/classes in QuickBooks after submission
    # When classification field is added to expense items, map it to Class ID using:
    #   client_module().query_class_by_name(classification_name)
    # or use query_all_classes() to get all classes and map user selection to ID
    bill_lines =
      expense_report.expense_items
      |> Enum.map(fn item ->
        amount = Money.to_decimal(item.amount) |> Decimal.to_float()

        # TODO: When classification field is added to ExpenseReportItem schema,
        # query for Class ID and set class_ref here instead of nil
        # Example:
        #   class_ref = case item.classification do
        #     nil -> nil
        #     classification_name ->
        #       case client_module().query_class_by_name(classification_name) do
        #         {:ok, class_id} -> %{value: class_id}
        #         _ -> nil
        #       end
        #   end

        %{
          description: "#{item.vendor} - #{item.description}",
          amount: amount,
          account_ref: %{value: default_expense_account_id || ""},
          class_ref: nil
        }
      end)

    # Use the earliest expense item date as the transaction date
    txn_date =
      expense_report.expense_items
      |> Enum.map(& &1.date)
      |> Enum.min()
      |> Date.to_iso8601()

    # Build private note with bank info if available
    private_note = build_private_note(expense_report)

    bill_params = %{
      vendor_ref: %{value: vendor_id},
      txn_date: txn_date,
      line: bill_lines,
      private_note: private_note
    }

    # Only set APAccountRef if we have an Accounts Payable account
    # QuickBooks will use a default if not specified, but it's better to be explicit
    bill_params =
      if ap_account_id do
        Map.put(bill_params, :ap_account_ref, %{value: ap_account_id})
      else
        bill_params
      end

    case client_module().create_bill(bill_params) do
      {:ok, bill} ->
        Logger.info("[QB Expense Sync] create_bill: Successfully created bill",
          bill_id: Map.get(bill, "Id"),
          expense_report_id: expense_report.id
        )

        {:ok, bill}

      {:error, reason} ->
        Logger.error("[QB Expense Sync] create_bill: Failed to create bill",
          expense_report_id: expense_report.id,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp build_private_note(%ExpenseReport{} = expense_report) do
    note_parts = ["Expense Report: #{expense_report.purpose}"]

    note_parts =
      case expense_report.reimbursement_method do
        "bank_transfer" ->
          if expense_report.bank_account do
            bank_account = expense_report.bank_account
            account_last_4 = bank_account.account_number_last_4 || "N/A"
            ["Bank Transfer - Account: ...#{account_last_4}" | note_parts]
          else
            ["Bank Transfer (account not specified)" | note_parts]
          end

        "check" ->
          if expense_report.address do
            addr = expense_report.address
            address_str = "#{addr.address}, #{addr.city}, #{addr.region} #{addr.postal_code}"
            ["Check - Ship to: #{address_str}" | note_parts]
          else
            ["Check (address not specified)" | note_parts]
          end

        _ ->
          note_parts
      end

    Enum.join(note_parts, " | ")
  end

  defp upload_and_link_receipts(%ExpenseReport{} = expense_report, bill_id) do
    Logger.debug("[QB Expense Sync] upload_and_link_receipts: Uploading receipts",
      expense_report_id: expense_report.id,
      bill_id: bill_id
    )

    # Upload receipts for expense items
    results =
      expense_report.expense_items
      |> Enum.filter(fn item -> item.receipt_s3_path && item.receipt_s3_path != "" end)
      |> Enum.map(fn item ->
        upload_receipt_to_quickbooks(item.receipt_s3_path, bill_id)
      end)

    # Check for any errors
    errors = Enum.filter(results, fn r -> match?({:error, _}, r) end)

    if Enum.any?(errors) do
      Logger.error("[QB Expense Sync] upload_and_link_receipts: Some receipts failed to upload",
        expense_report_id: expense_report.id,
        errors: Enum.map(errors, fn {:error, reason} -> inspect(reason) end)
      )

      # Don't fail the entire sync if receipt upload fails
      # The bill is created, receipts can be added manually later
      {:ok, :partial_success}
    else
      Logger.info(
        "[QB Expense Sync] upload_and_link_receipts: All receipts uploaded successfully",
        expense_report_id: expense_report.id
      )

      {:ok, :success}
    end
  end

  defp upload_receipt_to_quickbooks(s3_path, bill_id) do
    Logger.debug("[QB Expense Sync] upload_receipt_to_quickbooks: Uploading receipt",
      s3_path: s3_path,
      bill_id: bill_id
    )

    # Download file from S3 to temporary location
    with {:ok, temp_file_path} <- download_from_s3_to_temp(s3_path),
         {:ok, attachable_id} <- upload_to_quickbooks(temp_file_path, s3_path),
         {:ok, _} <- link_attachment_to_bill(attachable_id, bill_id) do
      # Clean up temp file
      File.rm(temp_file_path)
      {:ok, attachable_id}
    else
      {:error, reason} = error ->
        Logger.error("[QB Expense Sync] upload_receipt_to_quickbooks: Failed",
          s3_path: s3_path,
          error: inspect(reason)
        )

        error
    end
  end

  defp download_from_s3_to_temp(s3_path) do
    # Parse S3 path to get bucket and key
    # S3 paths can be in different formats:
    # - http://bucket.s3.localhost.localstack.cloud:4566/key
    # - https://bucket.fly.storage.tigris.dev/key
    # - /key (relative path)

    bucket = S3Config.expense_reports_bucket_name()
    key = extract_s3_key(s3_path)

    Logger.debug("[QB Expense Sync] download_from_s3_to_temp: Downloading from S3",
      bucket: bucket,
      key: key
    )

    # Create temp file
    temp_file = System.tmp_dir!() |> Path.join("qb_upload_#{:rand.uniform(1_000_000_000)}")

    # Download from S3 using ExAws
    case ExAws.S3.get_object(bucket, key) |> ExAws.request() do
      {:ok, %{body: body}} ->
        File.write!(temp_file, body)
        {:ok, temp_file}

      {:error, reason} ->
        Logger.error("[QB Expense Sync] download_from_s3_to_temp: Failed to download from S3",
          bucket: bucket,
          key: key,
          error: inspect(reason)
        )

        {:error, :s3_download_failed}
    end
  end

  defp extract_s3_key(s3_path) do
    # Remove protocol and domain, extract key
    # Also remove bucket name if it's included in the path
    bucket_name = S3Config.expense_reports_bucket_name()

    s3_path
    |> String.replace(~r/^https?:\/\/[^\/]+/, "")
    |> String.trim_leading("/")
    |> String.replace(~r/^#{Regex.escape(bucket_name)}\//, "")
  end

  defp upload_to_quickbooks(file_path, original_s3_path) do
    file_name = Path.basename(original_s3_path)
    content_type = get_content_type(file_path)

    client_module().upload_attachment(file_path, file_name, content_type)
  end

  defp get_content_type(file_path) do
    case Path.extname(file_path) |> String.downcase() do
      ".pdf" -> "application/pdf"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".webp" -> "image/webp"
      _ -> "application/octet-stream"
    end
  end

  defp link_attachment_to_bill(attachable_id, bill_id) do
    client_module().link_attachment_to_bill(attachable_id, bill_id)
  end

  defp update_sync_attempt_timestamp(%ExpenseReport{} = expense_report) do
    now = DateTime.utc_now()

    expense_report
    |> ExpenseReport.changeset(%{quickbooks_last_sync_attempt_at: now})
    |> Repo.update()
  end

  defp update_expense_report_success(
         %ExpenseReport{} = expense_report,
         vendor_id,
         bill_id
       ) do
    now = DateTime.utc_now()

    expense_report
    |> ExpenseReport.changeset(%{
      quickbooks_vendor_id: vendor_id,
      quickbooks_bill_id: bill_id,
      quickbooks_sync_status: "synced",
      quickbooks_sync_error: nil,
      quickbooks_synced_at: now
    })
    |> Repo.update()
  end

  defp update_expense_report_error(%ExpenseReport{} = expense_report, error) do
    error_message = if is_binary(error), do: error, else: inspect(error)

    Logger.debug(
      "[QB Expense Sync] update_expense_report_error: Updating expense report with error",
      expense_report_id: expense_report.id,
      error: error_message
    )

    case expense_report
         |> ExpenseReport.changeset(%{
           quickbooks_sync_status: "failed",
           quickbooks_sync_error: error_message
         })
         |> Repo.update() do
      {:ok, updated} ->
        Logger.debug("[QB Expense Sync] update_expense_report_error: Successfully updated",
          expense_report_id: updated.id,
          sync_status: updated.quickbooks_sync_status
        )

        {:ok, updated}

      {:error, changeset} ->
        Logger.error(
          "[QB Expense Sync] update_expense_report_error: Failed to update expense report",
          expense_report_id: expense_report.id,
          errors: inspect(changeset.errors)
        )

        {:error, changeset}
    end
  end
end
