defmodule YscWeb.Emails.ExpenseReportConfirmation do
  @moduledoc """
  Email template for expense report submission confirmation.

  Sends a confirmation email to users after they submit an expense report.
  """
  use MjmlEEx,
    mjml_template: "templates/expense_report_confirmation.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  alias Ysc.Repo
  alias Ysc.ExpenseReports.ExpenseReport

  def get_template_name() do
    "expense_report_confirmation"
  end

  def get_subject() do
    "Expense Report Submitted - Confirmation"
  end

  @doc """
  Prepares expense report confirmation email data.

  ## Parameters:
  - `expense_report`: The submitted expense report with preloaded associations

  ## Returns:
  - Map with all necessary data for the email template
  """
  def prepare_email_data(expense_report) do
    # Validate input
    if is_nil(expense_report) do
      raise ArgumentError, "Expense report cannot be nil"
    end

    if is_nil(expense_report.id) do
      raise ArgumentError, "Expense report missing id: #{inspect(expense_report)}"
    end

    # Ensure we have all necessary preloaded data
    expense_report =
      if Ecto.assoc_loaded?(expense_report.user) &&
           Ecto.assoc_loaded?(expense_report.expense_items) &&
           Ecto.assoc_loaded?(expense_report.income_items) do
        expense_report
      else
        case Repo.get(ExpenseReport, expense_report.id)
             |> Repo.preload([
               :user,
               :expense_items,
               :income_items,
               :event,
               :bank_account,
               :address
             ]) do
          nil ->
            raise ArgumentError, "Expense report not found: #{expense_report.id}"

          loaded_report ->
            loaded_report
        end
      end

    # Validate required associations
    if is_nil(expense_report.user) do
      raise ArgumentError, "Expense report missing user association: #{expense_report.id}"
    end

    # Format dates
    submitted_date = format_datetime(expense_report.inserted_at)

    # Calculate totals (handle nil or empty lists)
    expense_items_list = expense_report.expense_items || []
    income_items_list = expense_report.income_items || []

    expense_total =
      expense_items_list
      |> Enum.reduce(Money.new(0, :USD), fn item, acc ->
        if item.amount do
          case Money.add(acc, item.amount) do
            {:ok, new_total} -> new_total
            {:error, _} -> acc
          end
        else
          acc
        end
      end)

    income_total =
      income_items_list
      |> Enum.reduce(Money.new(0, :USD), fn item, acc ->
        if item.amount do
          case Money.add(acc, item.amount) do
            {:ok, new_total} -> new_total
            {:error, _} -> acc
          end
        else
          acc
        end
      end)

    # Money.sub also returns {:ok, result} or {:error, reason}
    net_total =
      case Money.sub(expense_total, income_total) do
        {:ok, result} -> result
        {:error, _} -> Money.new(0, :USD)
      end

    # Format expense items
    expense_items =
      expense_items_list
      |> Enum.map(fn item ->
        %{
          vendor: item.vendor || "N/A",
          description: item.description || "N/A",
          date: format_date(item.date),
          amount: format_money(item.amount),
          has_receipt: !is_nil(item.receipt_s3_path) && item.receipt_s3_path != ""
        }
      end)

    # Format income items
    income_items =
      income_items_list
      |> Enum.map(fn item ->
        %{
          description: item.description || "N/A",
          date: format_date(item.date),
          amount: format_money(item.amount),
          has_proof: !is_nil(item.proof_s3_path) && item.proof_s3_path != ""
        }
      end)

    # Format reimbursement method
    reimbursement_method = format_reimbursement_method(expense_report.reimbursement_method)

    # Get event info if present
    event_info =
      if expense_report.event do
        %{
          title: expense_report.event.title,
          id: expense_report.event.id,
          reference_id: expense_report.event.reference_id
        }
      else
        nil
      end

    # Get bank account info if present
    bank_account_info =
      if expense_report.bank_account do
        %{
          last_4: expense_report.bank_account.account_number_last_4 || "N/A"
        }
      else
        nil
      end

    %{
      first_name: expense_report.user.first_name || "Valued Member",
      expense_report: %{
        id: expense_report.id,
        purpose: expense_report.purpose || "N/A",
        submitted_date: submitted_date,
        reimbursement_method: reimbursement_method,
        expense_total: format_money(expense_total),
        income_total: format_money(income_total),
        net_total: format_money(net_total),
        expense_items: expense_items,
        income_items: income_items,
        event: event_info,
        bank_account: bank_account_info
      },
      expense_report_url: expense_report_url(expense_report.id)
    }
  end

  defp expense_report_url(expense_report_id) do
    YscWeb.Endpoint.url() <> "/expensereport/#{expense_report_id}/success"
  end

  defp format_reimbursement_method("bank_transfer"), do: "Bank Transfer"
  defp format_reimbursement_method("check"), do: "Check"
  defp format_reimbursement_method(method) when is_binary(method), do: String.capitalize(method)
  defp format_reimbursement_method(_), do: "Not specified"

  defp format_date(nil), do: "N/A"

  defp format_date(date) do
    Calendar.strftime(date, "%B %d, %Y")
  end

  defp format_datetime(nil), do: "N/A"

  defp format_datetime(datetime) do
    # Convert to PST
    pst_datetime = DateTime.shift_zone!(datetime, "America/Los_Angeles")
    Calendar.strftime(pst_datetime, "%B %d, %Y at %I:%M %p %Z")
  end

  defp format_money(%Money{} = money) do
    Money.to_string!(money, separator: ".", delimiter: ",", fractional_digits: 2)
  end

  defp format_money(_), do: "$0.00"
end
