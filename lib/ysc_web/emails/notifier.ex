defmodule YscWeb.Emails.Notifier do
  @moduledoc """
  Email notification service.

  Routes email templates to appropriate email modules based on template names.
  """
  import Swoosh.Email

  defp from_email do
    Application.get_env(:ysc, :emails)[:from_email] || "info@ysc.org"
  end

  defp from_name do
    Application.get_env(:ysc, :emails)[:from_name] || "YSC"
  end

  @template_mappings %{
    "application_rejected" => YscWeb.Emails.ApplicationRejected,
    "application_approved" => YscWeb.Emails.ApplicationApproved,
    "application_submitted" => YscWeb.Emails.ApplicationSubmitted,
    "confirm_email" => YscWeb.Emails.ConfirmEmail,
    "reset_password" => YscWeb.Emails.ResetPassword,
    "password_changed" => YscWeb.Emails.PasswordChanged,
    "change_email" => YscWeb.Emails.ChangeEmail,
    "email_changed" => YscWeb.Emails.EmailChanged,
    "admin_application_submitted" => YscWeb.Emails.AdminApplicationSubmitted,
    "conduct_violation_confirmation" => YscWeb.Emails.ConductViolationConfirmation,
    "conduct_violation_board_notification" => YscWeb.Emails.ConductViolationBoardNotification,
    "ticket_purchase_confirmation" => YscWeb.Emails.TicketPurchaseConfirmation,
    "ticket_order_refund" => YscWeb.Emails.TicketOrderRefund,
    "booking_confirmation" => YscWeb.Emails.BookingConfirmation,
    "booking_refund_processed" => YscWeb.Emails.BookingRefundProcessed,
    "booking_refund_pending" => YscWeb.Emails.BookingRefundPending,
    "volunteer_confirmation" => YscWeb.Emails.VolunteerConfirmation,
    "volunteer_board_notification" => YscWeb.Emails.VolunteerBoardNotification,
    "outage_notification" => YscWeb.Emails.OutageNotification,
    "membership_payment_failure" => YscWeb.Emails.MembershipPaymentFailure,
    "membership_renewal_success" => YscWeb.Emails.MembershipRenewalSuccess,
    "membership_payment_reminder_7day" => YscWeb.Emails.MembershipPaymentReminder7Day,
    "membership_payment_reminder_30day" => YscWeb.Emails.MembershipPaymentReminder30Day,
    "booking_checkin_reminder" => YscWeb.Emails.BookingCheckinReminder,
    "booking_checkout_reminder" => YscWeb.Emails.BookingCheckoutReminder,
    "event_notification" => YscWeb.Emails.EventNotification,
    "expense_report_confirmation" => YscWeb.Emails.ExpenseReportConfirmation,
    "expense_report_treasurer_notification" => YscWeb.Emails.ExpenseReportTreasurerNotification,
    "booking_cancellation_cabin_master_notification" =>
      YscWeb.Emails.BookingCancellationCabinMasterNotification,
    "booking_cancellation_treasurer_notification" =>
      YscWeb.Emails.BookingCancellationTreasurerNotification,
    "booking_cancellation_confirmation" => YscWeb.Emails.BookingCancellationConfirmation
  }

  def schedule_email(recipient, idempotency_key, subject, template, variables, text_body, user_id) do
    require Logger

    # Get category for this template
    category = Ysc.Accounts.EmailCategories.get_category(template)

    # Oban jobs require string keys in args
    job =
      %{
        "recipient" => recipient,
        "idempotency_key" => idempotency_key,
        "subject" => subject,
        "template" => template,
        "params" => variables,
        "text_body" => text_body,
        "user_id" => user_id,
        "category" => category
      }
      |> YscWeb.Workers.EmailNotifier.new()

    case Oban.insert(job) do
      {:ok, %Oban.Job{} = inserted_job} ->
        Logger.debug("Notifier.schedule_email: Email job inserted successfully",
          job_id: inserted_job.id,
          recipient: recipient,
          template: template,
          idempotency_key: idempotency_key
        )

        inserted_job

      {:error, reason} = error ->
        Logger.error(
          "Notifier.schedule_email: Failed to insert email job - Full error details:\n#{inspect(reason, limit: :infinity)}",
          recipient: recipient,
          template: template,
          idempotency_key: idempotency_key,
          error: inspect(reason, limit: :infinity),
          error_type:
            if(is_atom(reason),
              do: reason,
              else:
                if(is_map(reason) && Map.has_key?(reason, :__struct__),
                  do: inspect(reason.__struct__),
                  else: :unknown
                )
            )
        )

        # Report to Sentry with detailed context
        error_type =
          if(is_atom(reason),
            do: reason,
            else:
              if(is_map(reason) && Map.has_key?(reason, :__struct__),
                do: inspect(reason.__struct__),
                else: :unknown
              )
          )

        # If reason is a changeset, capture it as an exception
        if match?(%Ecto.Changeset{}, reason) do
          Sentry.capture_message("Failed to insert email job (Oban.insert returned changeset)",
            level: :error,
            extra: %{
              recipient: recipient,
              template: template,
              idempotency_key: idempotency_key,
              subject: subject,
              user_id: user_id,
              category: category,
              changeset_valid: reason.valid?,
              changeset_errors:
                if(reason.valid?, do: :none, else: inspect(reason.errors, limit: :infinity)),
              changeset_changes: inspect(reason.changes, limit: :infinity)
            },
            tags: %{
              email_template: template,
              email_category: to_string(category),
              error_type: "oban_insert_failed",
              has_user_id: !is_nil(user_id)
            }
          )
        else
          Sentry.capture_message("Failed to insert email job",
            level: :error,
            extra: %{
              recipient: recipient,
              template: template,
              idempotency_key: idempotency_key,
              subject: subject,
              user_id: user_id,
              category: category,
              error: inspect(reason, limit: :infinity),
              error_type: error_type
            },
            tags: %{
              email_template: template,
              email_category: to_string(category),
              error_type: "oban_insert_failed",
              has_user_id: !is_nil(user_id)
            }
          )
        end

        error
    end
  end

  def schedule_email(
        recipient,
        idempotency_key,
        subject,
        template,
        variables,
        text_body
      ) do
    schedule_email(recipient, idempotency_key, subject, template, variables, text_body, nil)
  end

  def schedule_email_to_board(idempotency_key, subject, template, variables) do
    schedule_email(from_email(), idempotency_key, subject, template, variables, "", nil)
  end

  def send_email_idempotent(
        recipient,
        idempotency_key,
        subject,
        template,
        variables,
        text_body,
        user_id
      ) do
    rendered = template.render(variables)
    template_name = template.get_template_name()

    attrs = %{
      message_type: :email,
      idempotency_key: idempotency_key,
      message_template: template_name,
      params: variables,
      email: recipient,
      rendered_message: rendered,
      user_id: user_id
    }

    email =
      new()
      |> to(recipient)
      |> from({from_name(), from_email()})
      |> subject(subject)
      |> html_body(rendered)
      |> text_body(text_body)

    Ysc.Messages.run_send_message_idempotent(email, attrs)
  end

  def send_email_idempotent(recipient, idempotency_key, subject, template, variables, text_body) do
    send_email_idempotent(
      recipient,
      idempotency_key,
      subject,
      template,
      variables,
      text_body,
      nil
    )
  end

  def send_email_to_board(idempotency_key, subject, template, variables) do
    send_email_idempotent(
      from_email(),
      idempotency_key,
      subject,
      template,
      variables,
      "",
      nil
    )
  end

  def get_template_module(template_name) do
    @template_mappings[template_name]
  end
end
