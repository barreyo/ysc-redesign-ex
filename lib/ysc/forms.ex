defmodule Ysc.Forms do
  import Ecto.Query, warn: false
  alias Ysc.Repo

  def create_volunteer(changeset) do
    case Repo.insert(changeset) do
      {:ok, volunteer} ->
        {:ok, volunteer}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def create_conduct_violation_report(changeset) do
    case Repo.insert(changeset) do
      {:ok, report} ->
        send_conduct_violation_emails(report)
        {:ok, report}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp send_conduct_violation_emails(report) do
    # Send confirmation email to reporter
    confirmation_variables = %{
      first_name: report.first_name,
      last_name: report.last_name,
      summary: report.summary
    }

    confirmation_idempotency_key = "conduct_violation_confirmation_#{report.id}"

    YscWeb.Emails.Notifier.schedule_email(
      report.email,
      confirmation_idempotency_key,
      YscWeb.Emails.ConductViolationConfirmation.get_subject(),
      "conduct_violation_confirmation",
      confirmation_variables,
      ""
    )

    # Send notification email to board
    board_variables = %{
      first_name: report.first_name,
      last_name: report.last_name,
      email: report.email,
      phone: report.phone,
      summary: report.summary,
      report_id: report.id,
      submitted_at: Calendar.strftime(report.inserted_at, "%B %d, %Y at %I:%M %p")
    }

    board_idempotency_key = "conduct_violation_board_notification_#{report.id}"

    YscWeb.Emails.Notifier.schedule_email_to_board(
      board_idempotency_key,
      YscWeb.Emails.ConductViolationBoardNotification.get_subject(),
      "conduct_violation_board_notification",
      board_variables
    )
  end
end
