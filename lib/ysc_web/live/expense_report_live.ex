defmodule YscWeb.ExpenseReportLive do
  use YscWeb, :live_view

  alias Ysc.ExpenseReports

  alias Ysc.ExpenseReports.{
    ExpenseReport,
    ExpenseReportItem,
    ExpenseReportIncomeItem,
    BankAccount
  }

  alias Ysc.Accounts
  alias Ysc.Accounts.User
  alias Ysc.Events
  alias Ysc.Repo

  import Ecto.Query
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if user && user.state == :active do
      expense_report = %ExpenseReport{
        user_id: user.id,
        reimbursement_method: "bank_transfer",
        expense_items: [%ExpenseReportItem{}],
        income_items: []
      }

      changeset = ExpenseReport.changeset(expense_report, %{})

      socket =
        socket
        |> assign(:form, to_form(changeset))
        |> assign(:expense_report, expense_report)
        |> assign(:totals, %{
          expense_total: Money.new(0, :USD),
          income_total: Money.new(0, :USD),
          net_total: Money.new(0, :USD)
        })
        |> assign(:bank_accounts, ExpenseReports.list_bank_accounts(user))
        |> assign(:billing_address, Accounts.get_billing_address(user))
        |> assign(:treasurer, get_treasurer())
        |> assign(:current_user, user)
        |> assign(:receipt_uploads, %{})
        |> assign(:proof_uploads, %{})
        |> assign(:bank_account_form, nil)
        |> assign(:events, Events.list_recent_and_upcoming_events())
        |> allow_upload(:receipt,
          accept: ~w(.pdf .jpg .jpeg .png .webp),
          max_entries: 10,
          max_file_size: 10_000_000,
          auto_upload: true
        )
        |> allow_upload(:proof,
          accept: ~w(.pdf .jpg .jpeg .png .webp),
          max_entries: 10,
          max_file_size: 10_000_000,
          auto_upload: true
        )

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, "You must be an active user to access this page.")
       |> redirect(to: ~p"/")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, params) do
    socket
    |> assign(:page_title, "New Expense Report")
    |> assign(:expense_report, nil)
    |> handle_modal_params(params)
  end

  defp apply_action(socket, :index, params) do
    socket
    |> assign(:page_title, "Expense Report")
    |> handle_modal_params(params)
  end

  defp apply_action(socket, :success, %{"id" => id}) do
    user = socket.assigns.current_user

    expense_report = ExpenseReports.get_expense_report!(id, user)
    totals = ExpenseReports.calculate_totals(expense_report)

    socket
    |> assign(:page_title, "Expense Report Submitted")
    |> assign(:expense_report, expense_report)
    |> assign(:totals, totals)
    |> assign(:bank_accounts, ExpenseReports.list_bank_accounts(user))
    |> assign(:billing_address, Accounts.get_billing_address(user))
  end

  defp handle_modal_params(socket, params) do
    case params do
      %{"modal" => "bank-account"} ->
        user = socket.assigns.current_user
        bank_account = %BankAccount{user_id: user.id}
        changeset = BankAccount.changeset(bank_account, %{})

        socket
        |> assign(:bank_account_form, to_form(changeset))

      _ ->
        socket
        |> assign(:bank_account_form, nil)
    end
  end

  @impl true
  def handle_event("validate", %{"expense_report" => expense_report_params}, socket) do
    user = socket.assigns.current_user

    # Preserve receipt_s3_path and proof_s3_path from existing changeset
    # These aren't in form params but are stored in the changeset
    # Also preserve items if they're missing from params (e.g., when only bank_account_id changes)
    current_changeset = socket.assigns.form.source

    expense_report_params =
      merge_existing_items_into_params(expense_report_params, current_changeset)
      |> normalize_params_keys()

    # Build changeset from params
    changeset =
      socket.assigns.expense_report
      |> ExpenseReport.changeset(expense_report_params)
      |> Map.put(:action, :validate)

    # Validate reimbursement setup
    changeset = validate_reimbursement_setup_in_liveview(changeset, user)

    totals = calculate_totals_from_changeset(changeset)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:totals, totals)}
  end

  def handle_event("recover", %{"expense_report" => expense_report_params}, socket) do
    # Custom recovery handler for form recovery after crash/disconnection
    # This ensures nested items and form state are properly restored
    user = socket.assigns.current_user

    # Normalize params to ensure all keys are strings (not mixed atoms/strings)
    expense_report_params = normalize_params_keys(expense_report_params)

    # Rebuild the expense report from params, ensuring we have at least one expense item
    expense_items = build_expense_items_from_params(expense_report_params["expense_items"] || %{})
    income_items = build_income_items_from_params(expense_report_params["income_items"] || %{})

    # Ensure at least one expense item exists
    expense_items = if Enum.empty?(expense_items), do: [%ExpenseReportItem{}], else: expense_items

    expense_report = %ExpenseReport{
      user_id: user.id,
      reimbursement_method: expense_report_params["reimbursement_method"] || "bank_transfer",
      expense_items: expense_items,
      income_items: income_items
    }

    changeset =
      expense_report
      |> ExpenseReport.changeset(expense_report_params)
      |> validate_reimbursement_setup_in_liveview(user)
      |> Map.put(:action, :validate)

    totals = calculate_totals_from_changeset(changeset)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:expense_report, expense_report)
     |> assign(:totals, totals)
     |> assign(:bank_accounts, ExpenseReports.list_bank_accounts(user))
     |> assign(:billing_address, Accounts.get_billing_address(user))}
  end

  def handle_event("add_expense_item", _params, socket) do
    changeset = socket.assigns.form.source

    expense_items =
      Ecto.Changeset.get_field(changeset, :expense_items, []) ++ [%ExpenseReportItem{}]

    new_changeset =
      changeset
      |> Ecto.Changeset.put_assoc(:expense_items, expense_items)

    totals = calculate_totals_from_changeset(new_changeset)

    {:noreply,
     socket
     |> assign(:form, to_form(new_changeset))
     |> assign(:totals, totals)}
  end

  def handle_event("clear_event", _params, socket) do
    changeset = socket.assigns.form.source
    expense_report = socket.assigns.expense_report

    # Update the expense_report struct first
    updated_expense_report = %{expense_report | event_id: nil}

    # Extract only simple field changes (not associations) and convert to string keys
    # Associations (expense_items, income_items) are handled by the data struct, not changes
    # Build a clean map with only string keys to avoid mixed key errors
    simple_field_changes =
      changeset.changes
      |> Enum.filter(fn
        {:expense_items, _} -> false
        {"expense_items", _} -> false
        {:income_items, _} -> false
        {"income_items", _} -> false
        # We'll set this explicitly below
        {:event_id, _} -> false
        # We'll set this explicitly below
        {"event_id", _} -> false
        _ -> true
      end)
      |> Enum.map(fn
        {key, value} when is_atom(key) -> {Atom.to_string(key), normalize_params_keys(value)}
        {key, value} -> {key, normalize_params_keys(value)}
      end)
      |> Enum.into(%{})
      |> Map.put("event_id", "")

    # Rebuild changeset from updated expense_report with string-key params
    new_changeset =
      updated_expense_report
      |> ExpenseReport.changeset(simple_field_changes)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(new_changeset))
     |> assign(:expense_report, updated_expense_report)}
  end

  def handle_event("remove_expense_item", %{"index" => index}, socket) do
    changeset = socket.assigns.form.source
    index = String.to_integer(index)

    expense_items =
      Ecto.Changeset.get_field(changeset, :expense_items, [])
      |> List.delete_at(index)

    # Ensure we always have at least one expense item to avoid Ecto association errors
    expense_items = if Enum.empty?(expense_items), do: [%ExpenseReportItem{}], else: expense_items

    new_changeset =
      changeset
      |> Ecto.Changeset.put_assoc(:expense_items, expense_items)

    totals = calculate_totals_from_changeset(new_changeset)

    {:noreply,
     socket
     |> assign(:form, to_form(new_changeset))
     |> assign(:totals, totals)}
  end

  def handle_event("add_income_item", _params, socket) do
    changeset = socket.assigns.form.source

    income_items =
      Ecto.Changeset.get_field(changeset, :income_items, []) ++ [%ExpenseReportIncomeItem{}]

    new_changeset =
      changeset
      |> Ecto.Changeset.put_assoc(:income_items, income_items)

    totals = calculate_totals_from_changeset(new_changeset)

    {:noreply,
     socket
     |> assign(:form, to_form(new_changeset))
     |> assign(:totals, totals)}
  end

  def handle_event("remove_income_item", %{"index" => index}, socket) do
    changeset = socket.assigns.form.source
    index = String.to_integer(index)

    income_items =
      Ecto.Changeset.get_field(changeset, :income_items, [])
      |> List.delete_at(index)

    new_changeset =
      changeset
      |> Ecto.Changeset.put_assoc(:income_items, income_items)

    totals = calculate_totals_from_changeset(new_changeset)

    {:noreply,
     socket
     |> assign(:form, to_form(new_changeset))
     |> assign(:totals, totals)}
  end

  def handle_event("validate-upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :receipt, ref)}
  end

  def handle_event("cancel-proof-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :proof, ref)}
  end

  def handle_event("consume-receipt", %{"ref" => ref, "index" => index}, socket) do
    index = String.to_integer(index)

    # Find the specific entry by ref
    entry =
      socket.assigns.uploads.receipt.entries
      |> Enum.find(fn entry -> to_string(entry.ref) == ref end)

    if entry do
      # Consume only this specific entry
      # The callback must return {:ok, value} or {:postpone, value}
      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          try do
            s3_path = ExpenseReports.upload_receipt_to_s3(path)
            # upload_receipt_to_s3 returns a string directly, not a tuple
            {:ok, s3_path}
          rescue
            e ->
              Logger.error("Error uploading receipt to S3", error: inspect(e))
              {:error, Exception.message(e)}
          catch
            :exit, reason ->
              Logger.error("Exit while uploading receipt to S3", reason: inspect(reason))
              {:error, "Upload failed: #{inspect(reason)}"}
          end
        end)

      case result do
        {:ok, s3_path} when is_binary(s3_path) ->
          changeset = socket.assigns.form.source

          expense_items =
            Ecto.Changeset.get_field(changeset, :expense_items, [])
            |> List.update_at(index, fn item ->
              Ecto.Changeset.change(item, receipt_s3_path: s3_path)
            end)

          new_changeset =
            changeset
            |> Ecto.Changeset.put_assoc(:expense_items, expense_items)

          {:noreply,
           socket
           |> assign(:form, to_form(new_changeset))
           |> put_flash(:info, "Receipt uploaded successfully")}

        {:postpone, _} ->
          {:noreply, socket |> put_flash(:error, "Upload is still in progress")}

        {:error, reason} ->
          Logger.error("Failed to upload receipt", reason: inspect(reason))
          {:noreply, socket |> put_flash(:error, "Failed to upload receipt: #{reason}")}

        # consume_uploaded_entry can return the value directly if callback returns {:ok, value}
        s3_path when is_binary(s3_path) ->
          Logger.debug("consume_uploaded_entry returned string directly", path: s3_path)
          changeset = socket.assigns.form.source

          expense_items =
            Ecto.Changeset.get_field(changeset, :expense_items, [])
            |> List.update_at(index, fn item ->
              Ecto.Changeset.change(item, receipt_s3_path: s3_path)
            end)

          new_changeset =
            changeset
            |> Ecto.Changeset.put_assoc(:expense_items, expense_items)

          {:noreply,
           socket
           |> assign(:form, to_form(new_changeset))
           |> put_flash(:info, "Receipt uploaded successfully")}

        other ->
          Logger.error("Unexpected result from consume_uploaded_entry",
            result: inspect(other, limit: 100)
          )

          {:noreply, socket |> put_flash(:error, "Failed to upload receipt: Unexpected result")}
      end
    else
      {:noreply, socket |> put_flash(:error, "Upload entry not found")}
    end
  end

  def handle_event("consume-proof", %{"ref" => ref, "index" => index}, socket) do
    index = String.to_integer(index)

    # Find the specific entry by ref
    entry =
      socket.assigns.uploads.proof.entries
      |> Enum.find(fn entry -> to_string(entry.ref) == ref end)

    if entry do
      # Consume only this specific entry
      # The callback must return {:ok, value} or {:postpone, value}
      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          try do
            s3_path = ExpenseReports.upload_receipt_to_s3(path)
            # upload_receipt_to_s3 returns a string directly, not a tuple
            {:ok, s3_path}
          rescue
            e ->
              Logger.error("Error uploading proof to S3", error: inspect(e))
              {:error, Exception.message(e)}
          catch
            :exit, reason ->
              Logger.error("Exit while uploading proof to S3", reason: inspect(reason))
              {:error, "Upload failed: #{inspect(reason)}"}
          end
        end)

      case result do
        {:ok, s3_path} when is_binary(s3_path) ->
          changeset = socket.assigns.form.source

          income_items =
            Ecto.Changeset.get_field(changeset, :income_items, [])
            |> List.update_at(index, fn item ->
              Ecto.Changeset.change(item, proof_s3_path: s3_path)
            end)

          new_changeset =
            changeset
            |> Ecto.Changeset.put_assoc(:income_items, income_items)

          {:noreply,
           socket
           |> assign(:form, to_form(new_changeset))
           |> put_flash(:info, "Proof document uploaded successfully")}

        {:postpone, _} ->
          {:noreply, socket |> put_flash(:error, "Upload is still in progress")}

        {:error, reason} ->
          Logger.error("Failed to upload proof", reason: inspect(reason))
          {:noreply, socket |> put_flash(:error, "Failed to upload proof: #{reason}")}

        # consume_uploaded_entry can return the value directly if callback returns {:ok, value}
        s3_path when is_binary(s3_path) ->
          Logger.debug("consume_uploaded_entry returned string directly", path: s3_path)
          changeset = socket.assigns.form.source

          income_items =
            Ecto.Changeset.get_field(changeset, :income_items, [])
            |> List.update_at(index, fn item ->
              Ecto.Changeset.change(item, proof_s3_path: s3_path)
            end)

          new_changeset =
            changeset
            |> Ecto.Changeset.put_assoc(:income_items, income_items)

          {:noreply,
           socket
           |> assign(:form, to_form(new_changeset))
           |> put_flash(:info, "Proof document uploaded successfully")}

        other ->
          Logger.error("Unexpected result from consume_uploaded_entry",
            result: inspect(other, limit: 100)
          )

          {:noreply, socket |> put_flash(:error, "Failed to upload proof: Unexpected result")}
      end
    else
      {:noreply, socket |> put_flash(:error, "Upload entry not found")}
    end
  end

  def handle_event("remove-receipt", %{"index" => index}, socket) do
    index = String.to_integer(index)
    changeset = socket.assigns.form.source

    expense_items =
      Ecto.Changeset.get_field(changeset, :expense_items, [])
      |> List.update_at(index, fn item ->
        Ecto.Changeset.change(item, receipt_s3_path: nil)
      end)

    new_changeset =
      changeset
      |> Ecto.Changeset.put_assoc(:expense_items, expense_items)

    totals = calculate_totals_from_changeset(new_changeset)

    {:noreply,
     socket
     |> assign(:form, to_form(new_changeset))
     |> assign(:totals, totals)}
  end

  def handle_event("remove-proof", %{"index" => index}, socket) do
    index = String.to_integer(index)
    changeset = socket.assigns.form.source

    income_items =
      Ecto.Changeset.get_field(changeset, :income_items, [])
      |> List.update_at(index, fn item ->
        Ecto.Changeset.change(item, proof_s3_path: nil)
      end)

    new_changeset =
      changeset
      |> Ecto.Changeset.put_assoc(:income_items, income_items)

    totals = calculate_totals_from_changeset(new_changeset)

    {:noreply,
     socket
     |> assign(:form, to_form(new_changeset))
     |> assign(:totals, totals)}
  end

  def handle_event("save", params, socket) do
    require Logger
    Logger.debug("HANDLE EVENT save", params: inspect(params, limit: :infinity))

    # Check if this is a submit action
    action =
      params["_action"] || (params["expense_report"] && params["expense_report"]["_action"])

    Logger.debug("Submit action check",
      action: action,
      has_action: Map.has_key?(params, "_action")
    )

    # Also check the form source for validation errors
    changeset = socket.assigns.form.source

    Logger.debug("Form validation",
      valid?: changeset.valid?,
      errors: inspect(changeset.errors, limit: 10)
    )

    if action == "submit" do
      Logger.debug("Processing submit action")
      expense_report_params = params["expense_report"] || %{}
      user = socket.assigns.current_user

      Logger.debug(
        "Before merge - expense_items count: #{map_size(expense_report_params["expense_items"] || %{})}"
      )

      # Preserve receipt/proof paths from current changeset before creating
      current_changeset = socket.assigns.form.source

      expense_report_params =
        merge_existing_items_into_params(expense_report_params, current_changeset)
        |> normalize_params_keys()
        |> Map.put("status", "submitted")

      Logger.debug(
        "After merge - expense_items count: #{map_size(expense_report_params["expense_items"] || %{})}, status: #{expense_report_params["status"]}"
      )

      Logger.debug(
        "Calling create_expense_report with purpose: #{inspect(expense_report_params["purpose"])}"
      )

      result = ExpenseReports.create_expense_report(expense_report_params, user)

      case result do
        {:ok, expense_report} ->
          Logger.debug(
            "create_expense_report SUCCESS - id: #{expense_report.id}, status: #{expense_report.status}"
          )

          # Expense report is already created with "submitted" status, no need to call submit_expense_report
          {:noreply,
           socket
           |> redirect(to: ~p"/expensereport/#{expense_report.id}/success")}

        {:error, changeset} ->
          Logger.error(
            "create_expense_report FAILED - errors: #{inspect(changeset.errors, limit: 20)}"
          )

          totals = calculate_totals_from_changeset(changeset)

          {:noreply,
           socket
           |> assign(:form, to_form(changeset))
           |> assign(:totals, totals)
           |> put_flash(:error, "Please fix the errors below before submitting")}
      end
    else
      # Not a submit action, just validate
      {:noreply, socket}
    end
  end

  def handle_event("open-bank-account-modal", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/expensereport?modal=bank-account")}
  end

  def handle_event("close-bank-account-modal", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/expensereport")}
  end

  def handle_event("noop", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("validate-bank-account", %{"bank_account" => bank_account_params}, socket) do
    user = socket.assigns.current_user
    bank_account = %BankAccount{user_id: user.id}

    changeset =
      bank_account
      |> BankAccount.changeset(bank_account_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:bank_account_form, to_form(changeset))}
  end

  def handle_event("save-bank-account", %{"bank_account" => bank_account_params}, socket) do
    user = socket.assigns.current_user

    case ExpenseReports.create_bank_account(bank_account_params, user) do
      {:ok, bank_account} ->
        # Refresh bank accounts list
        bank_accounts = ExpenseReports.list_bank_accounts(user)

        # Get current form and update bank_account_id if this is the first account
        changeset = socket.assigns.form.source

        new_bank_account_id =
          if length(bank_accounts) == 1,
            do: bank_account.id,
            else: Ecto.Changeset.get_field(changeset, :bank_account_id)

        updated_changeset =
          if new_bank_account_id do
            Ecto.Changeset.put_change(changeset, :bank_account_id, new_bank_account_id)
          else
            changeset
          end

        {:noreply,
         socket
         |> assign(:bank_accounts, bank_accounts)
         |> assign(:bank_account_form, nil)
         |> assign(:form, to_form(updated_changeset))
         |> push_patch(to: ~p"/expensereport")
         |> put_flash(:info, "Bank account added successfully")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:bank_account_form, to_form(changeset))}
    end
  end

  # Merges existing items from current changeset into params if they're missing
  # This ensures items and their receipt/proof paths are preserved when only
  # bank_account_id or reimbursement_method changes
  defp merge_existing_items_into_params(expense_report_params, current_changeset) do
    existing_expense_items = Ecto.Changeset.get_field(current_changeset, :expense_items, [])
    existing_income_items = Ecto.Changeset.get_field(current_changeset, :income_items, [])

    # Always merge receipt paths from existing items, even if expense_items are in params
    # This ensures receipt_s3_path is preserved when it's not in form params
    expense_items_params =
      if Map.has_key?(expense_report_params, "expense_items") &&
           expense_report_params["expense_items"] != %{} do
        # Merge receipt paths from existing items into params
        expense_report_params["expense_items"]
        |> Enum.map(fn {index, item_params} ->
          # Find matching existing item by index
          index_int =
            case Integer.parse(index) do
              {int, _} -> int
              :error -> 0
            end

          existing_item = Enum.at(existing_expense_items, index_int)

          existing_receipt_path =
            if existing_item, do: get_receipt_path_from_item(existing_item), else: nil

          # Preserve receipt path if it exists in the current changeset and isn't in params
          item_params =
            if existing_receipt_path && !Map.has_key?(item_params, "receipt_s3_path") do
              Map.put(item_params, "receipt_s3_path", existing_receipt_path)
            else
              item_params
            end

          {index, item_params}
        end)
        |> Enum.into(%{})
      else
        # Convert existing items to params format, preserving receipt_s3_path
        existing_expense_items
        |> Enum.with_index()
        |> Enum.into(%{}, fn {item, index} ->
          receipt_path = get_receipt_path_from_item(item)

          item_params = %{
            "_persistent_id" => to_string(index),
            "date" => format_date_for_input(item),
            "vendor" => get_field_from_item(item, :vendor),
            "description" => get_field_from_item(item, :description),
            "amount" => format_money_for_input(get_field_from_item(item, :amount))
          }

          item_params =
            if receipt_path,
              do: Map.put(item_params, "receipt_s3_path", receipt_path),
              else: item_params

          {to_string(index), item_params}
        end)
      end

    # Always merge proof paths from existing items, even if income_items are in params
    income_items_params =
      if Map.has_key?(expense_report_params, "income_items") &&
           expense_report_params["income_items"] != %{} do
        # Merge proof paths from existing items into params
        expense_report_params["income_items"]
        |> Enum.map(fn {index, item_params} ->
          # Find matching existing item by index
          index_int =
            case Integer.parse(index) do
              {int, _} -> int
              :error -> 0
            end

          existing_item = Enum.at(existing_income_items, index_int)

          existing_proof_path =
            if existing_item, do: get_proof_path_from_item(existing_item), else: nil

          # Preserve proof path if it exists in the current changeset and isn't in params
          item_params =
            if existing_proof_path && !Map.has_key?(item_params, "proof_s3_path") do
              Map.put(item_params, "proof_s3_path", existing_proof_path)
            else
              item_params
            end

          {index, item_params}
        end)
        |> Enum.into(%{})
      else
        # Convert existing items to params format, preserving proof_s3_path
        existing_income_items
        |> Enum.with_index()
        |> Enum.into(%{}, fn {item, index} ->
          proof_path = get_proof_path_from_item(item)

          item_params = %{
            "_persistent_id" => to_string(index),
            "date" => format_date_for_input(item),
            "description" => get_field_from_item(item, :description),
            "amount" => format_money_for_input(get_field_from_item(item, :amount))
          }

          item_params =
            if proof_path,
              do: Map.put(item_params, "proof_s3_path", proof_path),
              else: item_params

          {to_string(index), item_params}
        end)
      end

    expense_report_params
    |> Map.put("expense_items", expense_items_params)
    |> Map.put("income_items", income_items_params)
  end

  defp get_field_from_item(%Ecto.Changeset{} = item, field) do
    Ecto.Changeset.get_field(item, field)
  end

  defp get_field_from_item(%_{} = item, field) do
    Map.get(item, field)
  end

  defp get_field_from_item(_, _), do: nil

  # Normalize all keys in params to strings to avoid mixed key errors
  # This recursively converts all atom keys to string keys
  defp normalize_params_keys(params) when is_map(params) do
    # First, separate atom keys and string keys
    {atom_keys, string_keys} =
      Enum.split_with(params, fn {key, _value} -> is_atom(key) end)

    # Convert atom keys to strings and merge with string keys
    converted_atom_keys =
      atom_keys
      |> Enum.map(fn {key, value} -> {Atom.to_string(key), normalize_params_keys(value)} end)
      |> Enum.into(%{})

    # Convert string keys (recursively normalize nested values)
    converted_string_keys =
      string_keys
      |> Enum.map(fn {key, value} -> {key, normalize_params_keys(value)} end)
      |> Enum.into(%{})

    # Merge, with string keys taking precedence (in case of duplicates)
    Map.merge(converted_atom_keys, converted_string_keys)
  end

  defp normalize_params_keys(value), do: value

  defp format_date_for_input(nil), do: ""
  defp format_date_for_input(%Date{} = date), do: Date.to_string(date)
  defp format_date_for_input(_), do: ""

  defp get_proof_path_from_item(%Ecto.Changeset{} = item) do
    Ecto.Changeset.get_field(item, :proof_s3_path)
  end

  defp get_proof_path_from_item(%ExpenseReportIncomeItem{} = item) do
    item.proof_s3_path
  end

  defp get_proof_path_from_item(_), do: nil

  defp build_expense_items_from_params(items_params) when is_map(items_params) do
    items_params
    |> Enum.map(fn {_index, item_params} ->
      %ExpenseReportItem{
        date: parse_date(item_params["date"]),
        vendor: item_params["vendor"],
        description: item_params["description"],
        amount: parse_money(item_params["amount"]),
        receipt_s3_path: item_params["receipt_s3_path"]
      }
    end)
    |> Enum.filter(fn item -> not expense_item_empty?(item) end)
  end

  defp build_expense_items_from_params(_), do: []

  defp build_income_items_from_params(items_params) when is_map(items_params) do
    items_params
    |> Enum.map(fn {_index, item_params} ->
      %ExpenseReportIncomeItem{
        date: parse_date(item_params["date"]),
        description: item_params["description"],
        amount: parse_money(item_params["amount"]),
        proof_s3_path: item_params["proof_s3_path"]
      }
    end)
    |> Enum.filter(fn item -> not income_item_empty?(item) end)
  end

  defp build_income_items_from_params(_), do: []

  defp expense_item_empty?(%ExpenseReportItem{} = item) do
    is_nil(item.date) &&
      (is_nil(item.vendor) || item.vendor == "") &&
      (is_nil(item.description) || item.description == "") &&
      (is_nil(item.amount) || item.amount == Money.new(0, :USD))
  end

  defp income_item_empty?(%ExpenseReportIncomeItem{} = item) do
    is_nil(item.date) &&
      (is_nil(item.description) || item.description == "") &&
      (is_nil(item.amount) || item.amount == Money.new(0, :USD))
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_money(nil), do: nil
  defp parse_money(""), do: nil

  defp parse_money(amount_string) when is_binary(amount_string) do
    case Money.new(:USD, amount_string) do
      {:ok, money} -> money
      _ -> nil
    end
  end

  defp validate_reimbursement_setup_in_liveview(changeset, %User{} = user) do
    method = Ecto.Changeset.get_field(changeset, :reimbursement_method)

    case method do
      "bank_transfer" ->
        bank_account_id = Ecto.Changeset.get_field(changeset, :bank_account_id)
        bank_accounts = ExpenseReports.list_bank_accounts(user)

        cond do
          is_nil(bank_account_id) && length(bank_accounts) == 0 ->
            Ecto.Changeset.add_error(
              changeset,
              :reimbursement_method,
              "requires a bank account. Please add a bank account before submitting."
            )

          is_nil(bank_account_id) && length(bank_accounts) > 0 ->
            Ecto.Changeset.add_error(
              changeset,
              :bank_account_id,
              "must be selected. Please choose a bank account above."
            )

          true ->
            changeset
        end

      "check" ->
        address_id = Ecto.Changeset.get_field(changeset, :address_id)
        billing_address = Accounts.get_billing_address(user)

        cond do
          is_nil(billing_address) ->
            Ecto.Changeset.add_error(
              changeset,
              :reimbursement_method,
              "requires a billing address. Please add an address in your user settings."
            )

          is_nil(address_id) ->
            # Auto-set the billing address if available
            Ecto.Changeset.put_change(changeset, :address_id, billing_address.id)

          true ->
            changeset
        end

      _ ->
        changeset
    end
  end

  defp calculate_totals_from_changeset(changeset) do
    expense_items = Ecto.Changeset.get_field(changeset, :expense_items, [])
    income_items = Ecto.Changeset.get_field(changeset, :income_items, [])

    expense_total =
      expense_items
      |> Enum.map(fn item ->
        amount = get_amount_from_item(item)
        parse_amount_to_money(amount)
      end)
      |> Enum.reduce(Money.new(0, :USD), fn amount, acc ->
        case Money.add(acc, amount) do
          {:ok, result} -> result
          _ -> acc
        end
      end)

    income_total =
      income_items
      |> Enum.map(fn item ->
        amount = get_amount_from_item(item)
        parse_amount_to_money(amount)
      end)
      |> Enum.reduce(Money.new(0, :USD), fn amount, acc ->
        case Money.add(acc, amount) do
          {:ok, result} -> result
          _ -> acc
        end
      end)

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

  defp get_amount_from_item(%Ecto.Changeset{} = item) do
    Ecto.Changeset.get_field(item, :amount)
  end

  defp get_amount_from_item(item) when is_struct(item) do
    Map.get(item, :amount)
  end

  defp get_amount_from_item(item) when is_map(item) do
    Map.get(item, :amount) || Map.get(item, "amount")
  end

  defp get_amount_from_item(_), do: nil

  defp parse_amount_to_money(nil), do: Money.new(0, :USD)
  defp parse_amount_to_money(""), do: Money.new(0, :USD)
  defp parse_amount_to_money(%Money{} = money), do: money

  defp parse_amount_to_money(amount) when is_binary(amount) do
    case Money.new(:USD, amount) do
      {:ok, money} -> money
      _ -> Money.new(0, :USD)
    end
  end

  defp parse_amount_to_money(_), do: Money.new(0, :USD)

  @impl true
  def render(assigns) do
    case assigns.live_action do
      :success -> render_success(assigns)
      _ -> render_form(assigns)
    end
  end

  defp render_success(assigns) do
    ~H"""
    <div class="py-8 lg:py-10 max-w-screen-xl mx-auto px-4 lg:px-10">
      <div class="max-w-xl mx-auto">
        <!-- Success Header -->
        <div class="text-center mb-8">
          <div class="text-green-500 mb-4">
            <.icon name="hero-check-circle" class="w-16 h-16 mx-auto" />
          </div>
          <h1 class="text-3xl font-bold text-zinc-900 mb-2">Expense Report Submitted!</h1>
          <p class="text-zinc-600">
            Your expense report has been successfully submitted. You'll receive a confirmation email shortly.
          </p>
        </div>
        <!-- Expense Report Summary Card -->
        <div class="bg-white rounded-lg shadow-sm border border-zinc-200 mb-6">
          <div class="px-6 py-4 border-b border-zinc-200">
            <h2 class="text-lg font-semibold text-zinc-900">Expense Report Summary</h2>
          </div>
          <div class="px-6 py-4 space-y-4">
            <div>
              <dt class="text-sm font-medium text-zinc-500">Purpose</dt>
              <dd class="mt-1 text-sm text-zinc-900"><%= @expense_report.purpose %></dd>
            </div>
            <%= if @expense_report.event do %>
              <div>
                <dt class="text-sm font-medium text-zinc-500">Related Event</dt>
                <dd class="mt-1 text-sm text-zinc-900">
                  <%= @expense_report.event.title %> - <%= Calendar.strftime(
                    @expense_report.event.start_date,
                    "%B %d, %Y"
                  ) %>
                </dd>
              </div>
            <% end %>
            <div>
              <dt class="text-sm font-medium text-zinc-500">Report ID</dt>
              <dd class="mt-1 text-sm text-zinc-900 font-mono"><%= @expense_report.id %></dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-zinc-500">Submitted</dt>
              <dd class="mt-1 text-sm text-zinc-900">
                <%= Calendar.strftime(@expense_report.inserted_at, "%B %d, %Y at %I:%M %p") %>
              </dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-zinc-500">Reimbursement Method</dt>
              <dd class="mt-1 text-sm text-zinc-900">
                <%= case @expense_report.reimbursement_method do
                  "bank_transfer" -> "Bank Transfer"
                  "check" -> "Check"
                  _ -> "Not specified"
                end %>
              </dd>
            </div>
          </div>
        </div>
        <!-- Expense Items Card -->
        <div class="bg-white rounded-lg shadow-sm border border-zinc-200 mb-6">
          <div class="px-6 py-4 border-b border-zinc-200">
            <h2 class="text-lg font-semibold text-zinc-900">Expense Items</h2>
          </div>
          <div class="px-6 py-4">
            <div class="space-y-4">
              <%= if Enum.empty?(@expense_report.expense_items) do %>
                <p class="text-sm text-zinc-500">No expense items</p>
              <% else %>
                <%= for item <- @expense_report.expense_items do %>
                  <div class="flex justify-between items-start p-4 bg-zinc-50 rounded-lg">
                    <div class="flex-1">
                      <p class="font-medium text-zinc-900"><%= item.description %></p>
                      <p class="text-sm text-zinc-500 mt-1">
                        <%= if item.vendor do %>
                          Vendor: <%= item.vendor %> •
                        <% end %>
                        <%= if item.date do %>
                          Date: <%= Calendar.strftime(item.date, "%B %d, %Y") %>
                        <% end %>
                      </p>
                      <%= if item.receipt_s3_path do %>
                        <p class="text-xs text-green-600 mt-1">
                          <.icon name="hero-document-check" class="w-4 h-4 inline" /> Receipt attached
                        </p>
                      <% end %>
                    </div>
                    <div class="text-right ml-4">
                      <p class="font-semibold text-zinc-900">
                        <%= case Ysc.MoneyHelper.format_money(item.amount) do
                          {:ok, amount} -> amount
                          amount when is_binary(amount) -> amount
                          _ -> "N/A"
                        end %>
                      </p>
                    </div>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        </div>
        <!-- Income Items Card -->
        <%= if not Enum.empty?(@expense_report.income_items) do %>
          <div class="bg-white rounded-lg shadow-sm border border-zinc-200 mb-6">
            <div class="px-6 py-4 border-b border-zinc-200">
              <h2 class="text-lg font-semibold text-zinc-900">Income Items</h2>
            </div>
            <div class="px-6 py-4">
              <div class="space-y-4">
                <%= for item <- @expense_report.income_items do %>
                  <div class="flex justify-between items-start p-4 bg-zinc-50 rounded-lg">
                    <div class="flex-1">
                      <p class="font-medium text-zinc-900"><%= item.description %></p>
                      <p class="text-sm text-zinc-500 mt-1">
                        <%= if item.date do %>
                          Date: <%= Calendar.strftime(item.date, "%B %d, %Y") %>
                        <% end %>
                      </p>
                      <%= if item.proof_s3_path do %>
                        <p class="text-xs text-green-600 mt-1">
                          <.icon name="hero-document-check" class="w-4 h-4 inline" /> Proof attached
                        </p>
                      <% end %>
                    </div>
                    <div class="text-right ml-4">
                      <p class="font-semibold text-zinc-900">
                        <%= case Ysc.MoneyHelper.format_money(item.amount) do
                          {:ok, amount} -> amount
                          amount when is_binary(amount) -> amount
                          _ -> "N/A"
                        end %>
                      </p>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>
        <!-- Totals Card -->
        <div class="bg-white rounded-lg shadow-sm border border-zinc-200 mb-6">
          <div class="px-6 py-4 border-b border-zinc-200">
            <h2 class="text-lg font-semibold text-zinc-900">Totals</h2>
          </div>
          <div class="px-6 py-4">
            <div class="space-y-3">
              <div class="flex justify-between">
                <span class="text-zinc-600">Total Expenses</span>
                <span class="font-medium">
                  <%= case Ysc.MoneyHelper.format_money(@totals.expense_total) do
                    {:ok, amount} -> amount
                    amount when is_binary(amount) -> amount
                    _ -> "N/A"
                  end %>
                </span>
              </div>
              <%= if not Money.zero?(@totals.income_total) do %>
                <div class="flex justify-between">
                  <span class="text-zinc-600">Total Income</span>
                  <span class="font-medium">
                    <%= case Ysc.MoneyHelper.format_money(@totals.income_total) do
                      {:ok, amount} -> amount
                      amount when is_binary(amount) -> amount
                      _ -> "N/A"
                    end %>
                  </span>
                </div>
              <% end %>
              <div class="flex justify-between pt-3 border-t border-zinc-200">
                <span class="text-lg font-semibold text-zinc-900">Net Total</span>
                <span class="text-lg font-semibold text-zinc-900">
                  <%= case Ysc.MoneyHelper.format_money(@totals.net_total) do
                    {:ok, amount} -> amount
                    amount when is_binary(amount) -> amount
                    _ -> "N/A"
                  end %>
                </span>
              </div>
            </div>
          </div>
        </div>
        <!-- Confirmation Email Notice -->
        <div class="bg-blue-50 border border-blue-200 rounded-lg p-4 mb-6">
          <div class="flex">
            <div class="flex-shrink-0">
              <.icon name="hero-envelope" class="w-5 h-5 text-blue-600" />
            </div>
            <div class="ml-3">
              <h3 class="text-sm font-medium text-blue-800">Confirmation Email</h3>
              <div class="mt-2 text-sm text-blue-700">
                <p>
                  You will receive a confirmation email at <strong><%= @current_user.email %></strong>
                  with the details of your submitted expense report.
                </p>
              </div>
            </div>
          </div>
        </div>
        <!-- Actions -->
        <div class="flex justify-center space-x-4">
          <.link
            navigate={~p"/expensereport"}
            class="px-6 py-2 text-sm font-medium text-white bg-blue-600 rounded-md hover:bg-blue-700"
          >
            Submit Another Report
          </.link>
        </div>
      </div>
    </div>
    """
  end

  defp render_form(assigns) do
    ~H"""
    <div class="py-8 lg:py-10">
      <div class="flex flex-col space-y-6 max-w-screen-xl mx-auto px-4 lg:px-10">
        <div class="prose prose-zinc max-w-xl mx-auto lg:mx-0">
          <h1>Expense Report</h1>
          <p>
            Submit your expenses for reimbursement. Expenses must be submitted within 30 days of the date of purchase. Once submitted, you will receive an email confirmation and your reimbursement will be processed by the treasurer.
          </p>
          <p :if={@treasurer}>
            If you have questions, please contact:
            <strong><%= @treasurer.first_name %> <%= @treasurer.last_name %></strong>
            (<a href={"mailto:#{@treasurer.email}"} class="text-blue-600 hover:underline">
              <%= @treasurer.email %>
            </a>).
          </p>
        </div>

        <div class="max-w-xl mx-auto lg:mx-0">
          <.simple_form
            for={@form}
            id="expense-report-form"
            phx-submit="save"
            phx-change="validate"
            phx-auto-recover="recover"
            multipart={true}
          >
            <.input
              field={@form[:purpose]}
              type="textarea"
              label="Purpose"
              placeholder="What is the purpose of this expense report?"
              required
            />

            <div class="mt-4">
              <label
                for="expense_report_event_id"
                class="block text-sm font-semibold leading-6 text-zinc-800"
              >
                Related Event (Optional)
              </label>
              <div class="flex items-center gap-2 mt-2">
                <div>
                  <.input
                    field={@form[:event_id]}
                    type="select"
                    label=""
                    options={[
                      {"None - Not related to an event", ""}
                      | Enum.map(@events, fn event ->
                          label =
                            "#{event.title} - #{Calendar.strftime(event.start_date, "%B %d, %Y")}"

                          {label, event.id}
                        end)
                    ]}
                  />
                </div>
                <%= if Ecto.Changeset.get_field(@form.source, :event_id) do %>
                  <button
                    type="button"
                    phx-click="clear_event"
                    class="px-2 py-2 text-sm font-medium text-red-600 hover:text-red-800 border border-red-300 rounded-md hover:bg-red-50 h-10 flex items-center justify-center shrink-0"
                    title="Clear event selection"
                  >
                    <.icon name="hero-x-mark" class="w-4 h-4" />
                  </button>
                <% end %>
              </div>
              <p class="mt-1 text-sm text-zinc-500">
                If this expense report relates to an event, please select it to help with reporting.
                You can select from recent or upcoming events.
              </p>
            </div>

            <div class="space-y-6 mt-6">
              <div>
                <div class="mb-4">
                  <h3 class="text-lg font-semibold text-zinc-900">Expense Items</h3>
                </div>

                <.inputs_for :let={expense_f} field={@form[:expense_items]}>
                  <div class="border border-zinc-200 rounded-lg p-4 mb-4 space-y-4">
                    <div class="flex justify-between items-start">
                      <h4 class="text-md font-medium text-zinc-800">
                        Expense Item <%= expense_f.index + 1 %>
                      </h4>
                      <button
                        type="button"
                        phx-click="remove_expense_item"
                        phx-value-index={expense_f.index}
                        class="text-red-600 hover:text-red-800"
                      >
                        <.icon name="hero-x-mark" class="w-5 h-5 -mt-1 me-1" />Remove
                      </button>
                    </div>

                    <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                      <.input field={expense_f[:date]} type="date" label="Date" required />
                      <.input
                        field={expense_f[:vendor]}
                        type="text"
                        label="Vendor"
                        placeholder="Costco, Amazon, etc."
                        required
                      />
                    </div>

                    <.input
                      field={expense_f[:description]}
                      type="textarea"
                      label="Description"
                      placeholder="What did you buy?"
                      required
                    />

                    <.input
                      field={expense_f[:amount]}
                      type="text"
                      label="Amount"
                      phx-hook="MoneyInput"
                      value={format_money_for_input(expense_f[:amount].value)}
                      placeholder="0.00"
                      required
                    >
                      <div class="text-zinc-800">$</div>
                    </.input>

                    <div>
                      <label class="block text-sm font-medium text-zinc-700 mb-2">Receipt</label>
                      <p class="text-xs text-zinc-500 mb-3">
                        Upload a photo or PDF of your receipt. Accepted formats: PDF, JPG, JPEG, PNG, WEBP (max 10MB)
                      </p>
                      <!-- Show uploaded attachments -->
                      <div
                        :if={expense_f[:receipt_s3_path].value}
                        class="mb-3 p-3 bg-green-50 border border-green-200 rounded-lg"
                      >
                        <div class="flex items-center justify-between">
                          <div class="flex items-center gap-2">
                            <.icon name="hero-document-text" class="w-5 h-5 text-green-600" />
                            <span class="text-sm text-green-800 font-medium">Receipt attached</span>
                            <a
                              href={ExpenseReports.receipt_url(expense_f[:receipt_s3_path].value)}
                              target="_blank"
                              class="text-xs text-blue-600 hover:underline"
                            >
                              View
                            </a>
                          </div>
                          <button
                            type="button"
                            phx-click="remove-receipt"
                            phx-value-index={expense_f.index}
                            class="text-xs text-red-600 hover:text-red-800 font-medium"
                          >
                            Remove
                          </button>
                        </div>
                      </div>
                      <!-- Upload new receipt -->
                      <div
                        :if={!expense_f[:receipt_s3_path].value}
                        phx-drop-target={@uploads.receipt.ref}
                      >
                        <.live_file_input upload={@uploads.receipt} />
                        <%= for entry <- @uploads.receipt.entries do %>
                          <div class="mt-2">
                            <article class="upload-entry">
                              <div class="flex items-center gap-2">
                                <%= if is_pdf?(entry.client_name) do %>
                                  <div class="w-16 h-16 bg-red-50 border border-red-200 rounded flex items-center justify-center">
                                    <.icon name="hero-document-text" class="w-8 h-8 text-red-600" />
                                  </div>
                                <% else %>
                                  <.live_img_preview
                                    entry={entry}
                                    class="w-16 h-16 object-cover rounded"
                                  />
                                <% end %>
                                <div class="flex-1">
                                  <p class="text-sm text-zinc-700"><%= entry.client_name %></p>
                                  <progress value={entry.progress} max="100" class="w-full">
                                    <%= entry.progress %>%
                                  </progress>
                                </div>
                                <button
                                  type="button"
                                  phx-click="consume-receipt"
                                  phx-value-ref={entry.ref}
                                  phx-value-index={expense_f.index}
                                  disabled={entry.progress != 100}
                                  class="px-3 py-1 text-sm font-medium text-white bg-blue-600 rounded-md hover:bg-blue-700 disabled:bg-gray-400"
                                >
                                  Attach
                                </button>
                                <button
                                  type="button"
                                  phx-click="cancel-upload"
                                  phx-value-ref={entry.ref}
                                  class="px-3 py-1 text-sm font-medium text-red-600 rounded-md hover:bg-red-50"
                                >
                                  Cancel
                                </button>
                              </div>
                            </article>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  </div>
                </.inputs_for>

                <div class="mt-4">
                  <button
                    type="button"
                    phx-click="add_expense_item"
                    class="px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-md hover:bg-blue-700"
                  >
                    <.icon name="hero-plus" class="w-5 h-5 -mt-0.5 me-1" />Add Expense Item
                  </button>
                </div>
              </div>

              <div>
                <div class="mb-4">
                  <h3 class="text-lg font-semibold text-zinc-900">Income Items (Optional)</h3>
                </div>

                <.inputs_for :let={income_f} field={@form[:income_items]}>
                  <div class="border border-zinc-200 rounded-lg p-4 mb-4 space-y-4">
                    <div class="flex justify-between items-start">
                      <h4 class="text-md font-medium text-zinc-800">
                        Income Item <%= income_f.index + 1 %>
                      </h4>
                      <button
                        type="button"
                        phx-click="remove_income_item"
                        phx-value-index={income_f.index}
                        class="text-red-600 hover:text-red-800"
                      >
                        <.icon name="hero-x-mark" class="w-5 h-5 -mt-0.5 me-1" />Remove
                      </button>
                    </div>

                    <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                      <.input field={income_f[:date]} type="date" label="Date" required />
                      <.input
                        field={income_f[:amount]}
                        type="text"
                        label="Amount"
                        phx-hook="MoneyInput"
                        value={format_money_for_input(income_f[:amount].value)}
                        placeholder="0.00"
                        required
                      >
                        <div class="text-zinc-800">$</div>
                      </.input>
                    </div>

                    <.input
                      field={income_f[:description]}
                      type="textarea"
                      label="Description"
                      required
                    />

                    <div>
                      <label class="block text-sm font-medium text-zinc-700 mb-2">
                        Proof Document
                      </label>
                      <!-- Show uploaded attachments -->
                      <div
                        :if={income_f[:proof_s3_path].value}
                        class="mb-3 p-3 bg-green-50 border border-green-200 rounded-lg"
                      >
                        <div class="flex items-center justify-between">
                          <div class="flex items-center gap-2">
                            <.icon name="hero-document-text" class="w-5 h-5 text-green-600" />
                            <span class="text-sm text-green-800 font-medium">
                              Proof document attached
                            </span>
                            <a
                              href={ExpenseReports.receipt_url(income_f[:proof_s3_path].value)}
                              target="_blank"
                              class="text-xs text-blue-600 hover:underline"
                            >
                              View
                            </a>
                          </div>
                          <button
                            type="button"
                            phx-click="remove-proof"
                            phx-value-index={income_f.index}
                            class="text-xs text-red-600 hover:text-red-800 font-medium"
                          >
                            Remove
                          </button>
                        </div>
                      </div>
                      <!-- Upload new proof document -->
                      <div :if={!income_f[:proof_s3_path].value} phx-drop-target={@uploads.proof.ref}>
                        <.live_file_input upload={@uploads.proof} />
                        <%= for entry <- @uploads.proof.entries do %>
                          <div class="mt-2">
                            <article class="upload-entry">
                              <div class="flex items-center gap-2">
                                <%= if is_pdf?(entry.client_name) do %>
                                  <div class="w-16 h-16 bg-red-50 border border-red-200 rounded flex items-center justify-center">
                                    <.icon name="hero-document-text" class="w-8 h-8 text-red-600" />
                                  </div>
                                <% else %>
                                  <.live_img_preview
                                    entry={entry}
                                    class="w-16 h-16 object-cover rounded"
                                  />
                                <% end %>
                                <div class="flex-1">
                                  <p class="text-sm text-zinc-700"><%= entry.client_name %></p>
                                  <progress value={entry.progress} max="100" class="w-full">
                                    <%= entry.progress %>%
                                  </progress>
                                </div>
                                <button
                                  type="button"
                                  phx-click="consume-proof"
                                  phx-value-ref={entry.ref}
                                  phx-value-index={income_f.index}
                                  disabled={entry.progress != 100}
                                  class="px-3 py-1 text-sm font-medium text-white bg-blue-600 rounded-md hover:bg-blue-700 disabled:bg-gray-400"
                                >
                                  Attach
                                </button>
                                <button
                                  type="button"
                                  phx-click="cancel-proof-upload"
                                  phx-value-ref={entry.ref}
                                  class="px-3 py-1 text-sm font-medium text-red-600 rounded-md hover:bg-red-50"
                                >
                                  Cancel
                                </button>
                              </div>
                            </article>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  </div>
                </.inputs_for>

                <div class="mt-4">
                  <button
                    type="button"
                    phx-click="add_income_item"
                    class="px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-md hover:bg-blue-700"
                  >
                    <.icon name="hero-plus" class="w-5 h-5 -mt-0.5 me-1" />Add Income Item
                  </button>
                </div>
              </div>
            </div>

            <div class="mt-6 p-4 bg-zinc-50 rounded-lg">
              <h3 class="text-lg font-semibold text-zinc-900 mb-4">Summary</h3>
              <div class="space-y-2">
                <div class="flex justify-between">
                  <span class="text-zinc-700">Total Expenses:</span>
                  <span class="font-semibold"><%= Money.to_string!(@totals.expense_total) %></span>
                </div>
                <div class="flex justify-between">
                  <span class="text-zinc-700">Total Income:</span>
                  <span class="font-semibold"><%= Money.to_string!(@totals.income_total) %></span>
                </div>
                <div class="flex justify-between pt-2 border-t border-zinc-300">
                  <span class="text-lg font-semibold text-zinc-900">Net Total:</span>
                  <span class="text-lg font-bold"><%= Money.to_string!(@totals.net_total) %></span>
                </div>
              </div>
            </div>

            <div class="mt-6">
              <h3 class="text-lg font-semibold text-zinc-900 mb-4">Reimbursement Method</h3>

              <div class="mb-4 p-3 bg-green-50 border border-green-200 rounded-lg">
                <p class="text-sm text-green-800">
                  <strong>Bank Transfer is preferred</strong>
                  - Checks cost $1.50 each and take longer to process.
                </p>
              </div>

              <.input
                field={@form[:reimbursement_method]}
                type="select"
                label="How would you like to receive reimbursement?"
                options={[{"Bank Transfer (Preferred)", "bank_transfer"}, {"Check", "check"}]}
                required
              />

              <div
                :if={@form[:reimbursement_method].value == "check"}
                class="mt-4 p-4 bg-blue-50 rounded-lg border border-blue-200"
              >
                <h4 class="font-semibold text-zinc-900 mb-2">Check Mailing Address</h4>
                <p :if={@billing_address} class="text-sm text-zinc-700 mb-2">
                  Your check will be mailed to:
                </p>
                <p :if={@billing_address} class="text-sm font-medium text-zinc-900 mb-4">
                  <%= format_address(@billing_address) %>
                </p>
                <p :if={@billing_address} class="text-xs text-zinc-600">
                  To update this address, please visit your
                  <.link navigate={~p"/users/settings"} class="text-blue-600 hover:underline">
                    user settings
                  </.link>
                  before submitting.
                </p>
                <div
                  :if={!@billing_address}
                  class="p-3 bg-yellow-50 border border-yellow-200 rounded-lg"
                >
                  <p class="text-sm text-yellow-800 font-medium mb-2">
                    <strong>No address on file.</strong>
                  </p>
                  <p class="text-sm text-yellow-700">
                    Please update your address in
                    <.link
                      navigate={~p"/users/settings"}
                      class="text-blue-600 hover:underline font-medium"
                    >
                      user settings
                    </.link>
                    before submitting.
                  </p>
                </div>
                <.error :for={error <- @form[:reimbursement_method].errors}>
                  <%= error_to_string(error) %>
                </.error>
                <.error :for={error <- @form[:address_id].errors}>
                  <%= error_to_string(error) %>
                </.error>
              </div>

              <div :if={@form[:reimbursement_method].value == "bank_transfer"} class="mt-4">
                <h4 class="font-semibold text-zinc-900 mb-2">Bank Account</h4>
                <div :if={length(@bank_accounts) > 0} class="space-y-3">
                  <.input
                    field={@form[:bank_account_id]}
                    type="select"
                    label="Select Bank Account"
                    options={
                      [{"-- Select Bank Account --", ""}] ++
                        Enum.map(@bank_accounts, fn ba ->
                          {"****#{ba.account_number_last_4}", ba.id}
                        end)
                    }
                    required
                  />
                  <.error :for={error <- @form[:bank_account_id].errors}>
                    <%= error_to_string(error) %>
                  </.error>
                  <div class="flex items-center gap-2">
                    <span class="text-sm text-zinc-600">Or</span>
                    <button
                      type="button"
                      phx-click="open-bank-account-modal"
                      class="text-sm text-blue-600 hover:text-blue-800 hover:underline font-medium"
                    >
                      add a new bank account
                    </button>
                  </div>
                </div>
                <div :if={length(@bank_accounts) == 0} class="space-y-3">
                  <div class="p-4 bg-yellow-50 border border-yellow-200 rounded-lg">
                    <p class="text-sm text-yellow-800 font-medium mb-2">
                      <strong>No bank account on file.</strong>
                    </p>
                    <p class="text-sm text-yellow-700">
                      Please add a bank account to continue.
                    </p>
                  </div>
                  <button
                    type="button"
                    phx-click="open-bank-account-modal"
                    class="px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-md hover:bg-blue-700"
                  >
                    Add Bank Account
                  </button>
                </div>
                <.error :for={error <- @form[:reimbursement_method].errors}>
                  <%= error_to_string(error) %>
                </.error>
              </div>
            </div>

            <:actions>
              <div class="space-y-4">
                <!-- Certification checkbox -->
                <div class="p-4 bg-zinc-50 border border-zinc-200 rounded-lg">
                  <.input
                    field={@form[:certification_accepted]}
                    type="checkbox"
                    label={
                      user_name =
                        cond do
                          @current_user.first_name && @current_user.last_name ->
                            "#{@current_user.first_name} #{@current_user.last_name}"

                          @current_user.display_name ->
                            @current_user.display_name

                          true ->
                            @current_user.email
                        end

                      "I, #{user_name}, certify that the attached receipts or invoices represent legitimate expenses incurred solely for the benefit of YSC. I also certify that I have not been previously reimbursed for these expenses."
                    }
                    required
                  />
                </div>
                <!-- Error messages above button with fixed height to prevent layout shift -->
                <div class="min-h-[60px] space-y-1">
                  <%= if !can_submit?(@form, @bank_accounts, @billing_address, @current_user) do %>
                    <%= for error <- get_submission_errors(@form, @bank_accounts, @billing_address, @current_user) do %>
                      <p class="text-sm text-red-600"><%= error %></p>
                    <% end %>
                  <% end %>
                </div>
                <!-- Fixed-size submit button -->
                <.button
                  type="submit"
                  name="_action"
                  value="submit"
                  phx-disable-with="Submitting..."
                  disabled={!can_submit?(@form, @bank_accounts, @billing_address, @current_user)}
                  class={
                    "w-full sm:w-auto min-w-[180px] h-[42px] px-4 py-2 text-sm font-medium rounded-md " <>
                      if(can_submit?(@form, @bank_accounts, @billing_address, @current_user),
                        do: "text-white bg-green-600 hover:bg-green-700",
                        else: "text-zinc-400 bg-zinc-300 cursor-not-allowed"
                      )
                  }
                >
                  Submit for Review
                </.button>
              </div>
            </:actions>
          </.simple_form>
        </div>
      </div>
      <!-- Bank Account Modal -->
      <%= if @bank_account_form do %>
        <div class="fixed inset-0 z-50 overflow-y-auto" id="modal-backdrop">
          <div
            class="fixed inset-0 transition-opacity bg-zinc-500 bg-opacity-75"
            phx-click="close-bank-account-modal"
            aria-hidden="true"
          >
          </div>
          <div class="flex items-center justify-center min-h-screen px-4 pt-4 pb-20 text-center sm:block sm:p-0">
            <span class="hidden sm:inline-block sm:align-middle sm:h-screen" aria-hidden="true">
              &#8203;
            </span>

            <div
              class="inline-block align-bottom bg-white rounded-lg text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-3xl sm:w-full"
              phx-click-away="close-bank-account-modal"
              phx-click="noop"
            >
              <div class="bg-white px-4 pt-5 pb-4 sm:p-6 sm:pb-4">
                <div class="flex items-center justify-between mb-4">
                  <h3 class="text-lg font-medium leading-6 text-zinc-900">Add Bank Account</h3>
                  <button
                    type="button"
                    phx-click="close-bank-account-modal"
                    class="text-zinc-400 hover:text-zinc-500"
                  >
                    <span class="sr-only">Close</span>
                    <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M6 18L18 6M6 6l12 12"
                      />
                    </svg>
                  </button>
                </div>
                <!-- Illustration showing where to find routing and account numbers -->
                <div class="mb-6 p-4 bg-blue-50 border border-blue-200 rounded-lg">
                  <p class="text-sm font-medium text-blue-900 mb-3">Where to find your numbers:</p>
                  <!-- Mobile-only text instructions -->
                  <div class="md:hidden space-y-3">
                    <div class="text-sm text-blue-800">
                      <p class="font-semibold mb-2">On a check:</p>
                      <ul class="list-disc list-inside space-y-1 ml-2">
                        <li>Look at the bottom of your check</li>
                        <li>You'll see a line of numbers printed in magnetic ink (MICR line)</li>
                        <li>The first 9-digit number is your <strong>routing number</strong></li>
                        <li>
                          The number after the routing number is your <strong>account number</strong>
                        </li>
                      </ul>
                    </div>
                    <div class="text-sm text-blue-800 pt-2 border-t border-blue-300">
                      <p class="font-semibold mb-2">On a bank statement:</p>
                      <ul class="list-disc list-inside space-y-1 ml-2">
                        <li>Check your online banking or paper statement</li>
                        <li>The routing number is usually shown as "ABA" or "Routing #"</li>
                        <li>The account number is typically listed as "Account #"</li>
                      </ul>
                    </div>
                  </div>
                  <!-- Desktop illustration (hidden on mobile) -->
                  <div class="hidden md:block relative bg-white border-2 border-zinc-300 rounded-lg p-6 shadow-md max-w-2xl mx-auto">
                    <!-- Realistic Check Illustration - Rectangular like a real check -->
                    <div class="space-y-3" style="aspect-ratio: 2.5 / 1; min-height: 200px;">
                      <!-- Check Header -->
                      <div class="flex justify-between items-start border-b-2 border-zinc-400 pb-2">
                        <div class="text-base font-semibold text-zinc-800">YOUR BANK NAME</div>
                        <div class="text-xs text-zinc-500">No. 1234</div>
                      </div>
                      <!-- Main check body - side by side layout -->
                      <div class="grid grid-cols-3 gap-4 pt-2">
                        <!-- Left side: Date and Pay To -->
                        <div class="col-span-2 space-y-2">
                          <div class="flex justify-between items-center">
                            <span class="text-xs text-zinc-500">Date:</span>
                            <span class="text-xs text-zinc-400">MM/DD/YYYY</span>
                          </div>
                          <div class="border-b border-zinc-300 pb-1">
                            <div class="text-xs text-zinc-500 mb-1">Pay to the order of</div>
                            <div class="text-sm text-zinc-400">_________________________</div>
                          </div>
                          <div class="flex justify-between items-center border-b border-zinc-300 pb-1">
                            <div class="text-xs text-zinc-500">$</div>
                            <div class="text-sm text-zinc-400 flex-1 text-right">
                              _________________________
                            </div>
                          </div>
                        </div>
                        <!-- Right side: Memo and Signature -->
                        <div class="space-y-2">
                          <div>
                            <div class="text-xs text-zinc-500 mb-1">Memo:</div>
                            <div class="text-xs text-zinc-400 border-b border-zinc-300 pb-1">
                              _____________
                            </div>
                          </div>
                          <div>
                            <div class="text-xs text-zinc-500 mb-1">Signature</div>
                            <div class="text-xs text-zinc-400">_____________</div>
                          </div>
                        </div>
                      </div>
                      <!-- MICR Line (Bottom of Check) - This is where the numbers are -->
                      <div class="mt-4 pt-3 border-t-2 border-zinc-400 bg-zinc-50 rounded px-3 py-2">
                        <div class="text-xs text-zinc-500 mb-2 font-medium">
                          Bottom of check (MICR line):
                        </div>
                        <div class="flex items-center gap-2 font-mono text-sm">
                          <!-- Routing Number -->
                          <div class="flex items-center gap-1">
                            <div class="px-2 py-1 bg-blue-100 border-2 border-blue-400 border-dashed rounded">
                              <div class="text-xs text-blue-600 font-semibold">021000021</div>
                            </div>
                            <svg
                              class="w-4 h-4 text-blue-600 flex-shrink-0"
                              fill="none"
                              viewBox="0 0 24 24"
                              stroke="currentColor"
                            >
                              <path
                                stroke-linecap="round"
                                stroke-linejoin="round"
                                stroke-width="2"
                                d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                              />
                            </svg>
                          </div>
                          <!-- Separator symbols (typical on MICR line) -->
                          <span class="text-zinc-400">⦁</span>
                          <!-- Account Number -->
                          <div class="flex items-center gap-1">
                            <div class="px-2 py-1 bg-blue-100 border-2 border-blue-400 border-dashed rounded">
                              <div class="text-xs text-blue-600 font-semibold">1234567890</div>
                            </div>
                            <svg
                              class="w-4 h-4 text-blue-600 flex-shrink-0"
                              fill="none"
                              viewBox="0 0 24 24"
                              stroke="currentColor"
                            >
                              <path
                                stroke-linecap="round"
                                stroke-linejoin="round"
                                stroke-width="2"
                                d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                              />
                            </svg>
                          </div>
                        </div>
                        <div class="mt-2 text-xs text-zinc-600">
                          <div class="flex items-center gap-2">
                            <span class="font-medium text-blue-700">Routing Number</span>
                            <span class="text-zinc-400">•</span>
                            <span class="font-medium text-blue-700">Account Number</span>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                  <!-- Tip (hidden on mobile since we have text instructions) -->
                  <div class="hidden md:block pt-2 border-t border-zinc-200">
                    <p class="text-xs text-zinc-500 italic">
                      💡 Tip: These numbers are printed in magnetic ink at the bottom of your check
                    </p>
                  </div>
                </div>

                <.simple_form
                  for={@bank_account_form}
                  id="bank-account-form"
                  phx-submit="save-bank-account"
                  phx-change="validate-bank-account"
                >
                  <.input
                    field={@bank_account_form[:routing_number]}
                    type="text"
                    label="Routing Number"
                    required
                    maxlength="9"
                    placeholder="123456789"
                  />
                  <.input
                    field={@bank_account_form[:account_number]}
                    type="text"
                    label="Account Number"
                    required
                    placeholder="Account number"
                  />

                  <div class="mt-4 flex justify-end gap-3">
                    <button
                      type="button"
                      phx-click="close-bank-account-modal"
                      class="px-4 py-2 text-sm font-medium text-zinc-700 bg-white border border-zinc-300 rounded-md hover:bg-zinc-50"
                    >
                      Cancel
                    </button>
                    <.button>Add Bank Account</.button>
                  </div>
                </.simple_form>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp format_address(address) do
    [
      address.address,
      address.city,
      address.region,
      address.postal_code,
      address.country
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp format_money_for_input(nil), do: ""

  defp format_money_for_input(%Money{} = money) do
    case Ysc.MoneyHelper.format_money(money) do
      {:ok, formatted} -> formatted
      formatted when is_binary(formatted) -> formatted
      _ -> ""
    end
  end

  defp format_money_for_input(_), do: ""

  defp is_pdf?(filename) when is_binary(filename) do
    String.downcase(filename) |> String.ends_with?(".pdf")
  end

  defp is_pdf?(_), do: false

  defp can_submit?(form, bank_accounts, billing_address, _user) do
    # Check certification
    certification_accepted =
      form[:certification_accepted].value == true ||
        form[:certification_accepted].value == "true"

    # Check reimbursement method requirements
    method = form[:reimbursement_method].value

    reimbursement_valid =
      case method do
        "bank_transfer" ->
          bank_account_id = form[:bank_account_id].value
          length(bank_accounts) > 0 && !is_nil(bank_account_id) && bank_account_id != ""

        "check" ->
          !is_nil(billing_address)

        _ ->
          false
      end

    # Check that all expense items have receipts
    changeset = form.source
    expense_items = Ecto.Changeset.get_field(changeset, :expense_items, [])

    all_expense_items_have_receipts =
      expense_items
      |> Enum.all?(fn item ->
        receipt_path = get_receipt_path_from_item(item)
        !is_nil(receipt_path) && receipt_path != ""
      end)

    certification_accepted && reimbursement_valid && all_expense_items_have_receipts
  end

  defp get_receipt_path_from_item(%Ecto.Changeset{} = item) do
    Ecto.Changeset.get_field(item, :receipt_s3_path)
  end

  defp get_receipt_path_from_item(%ExpenseReportItem{} = item) do
    item.receipt_s3_path
  end

  defp get_receipt_path_from_item(_), do: nil

  defp get_submission_errors(form, bank_accounts, billing_address, _user) do
    errors = []

    # Check certification
    certification_accepted =
      form[:certification_accepted].value == true ||
        form[:certification_accepted].value == "true"

    errors =
      if !certification_accepted do
        errors ++ ["You must accept the certification to submit"]
      else
        errors
      end

    # Check reimbursement method requirements
    method = form[:reimbursement_method].value

    reimbursement_error =
      case method do
        "bank_transfer" ->
          bank_account_id = form[:bank_account_id].value

          if length(bank_accounts) == 0 do
            "Please add a bank account before submitting."
          else
            if is_nil(bank_account_id) || bank_account_id == "" do
              "Please select a bank account for bank transfer."
            else
              nil
            end
          end

        "check" ->
          if is_nil(billing_address) do
            "Please add a billing address in your user settings before submitting."
          else
            nil
          end

        _ ->
          "Please select a reimbursement method."
      end

    errors = if reimbursement_error, do: [reimbursement_error | errors], else: errors

    # Check that all expense items have receipts
    changeset = form.source
    expense_items = Ecto.Changeset.get_field(changeset, :expense_items, [])

    items_without_receipts =
      expense_items
      |> Enum.with_index()
      |> Enum.filter(fn {item, _index} ->
        receipt_path = get_receipt_path_from_item(item)
        is_nil(receipt_path) || receipt_path == ""
      end)

    errors =
      if Enum.any?(items_without_receipts) do
        ["All expense items must have a receipt attached before submission." | errors]
      else
        errors
      end

    errors
  end

  defp error_to_string({msg, _opts}), do: msg

  defp get_treasurer do
    from(u in User, where: u.board_position == "treasurer" and u.state == :active)
    |> Repo.one()
  end
end
