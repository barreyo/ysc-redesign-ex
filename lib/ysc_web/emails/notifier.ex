defmodule YscWeb.Emails.Notifier do
  @moduledoc """
  Email notification service.

  Routes email templates to appropriate email modules based on template names.
  """
  import Swoosh.Email

  @from_email "info@ysc.org"
  @from_name "YSC"

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
    "volunteer_confirmation" => YscWeb.Emails.VolunteerConfirmation,
    "volunteer_board_notification" => YscWeb.Emails.VolunteerBoardNotification,
    "outage_notification" => YscWeb.Emails.OutageNotification
  }

  def schedule_email(recipient, idempotency_key, subject, template, variables, text_body, user_id) do
    require Logger

    job =
      %{
        recipient: recipient,
        idempotency_key: idempotency_key,
        subject: subject,
        template: template,
        params: variables,
        text_body: text_body,
        user_id: user_id
      }
      |> YscWeb.Workers.EmailNotifier.new()

    case Oban.insert(job) do
      {:ok, %Oban.Job{} = inserted_job} ->
        Logger.debug("Email job inserted successfully",
          job_id: inserted_job.id,
          recipient: recipient,
          template: template,
          idempotency_key: idempotency_key
        )

        inserted_job

      {:error, reason} = error ->
        Logger.error("Failed to insert email job",
          recipient: recipient,
          template: template,
          idempotency_key: idempotency_key,
          error: inspect(reason)
        )

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
    schedule_email(@from_email, idempotency_key, subject, template, variables, "", nil)
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
      |> from({@from_name, @from_email})
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
      @from_email,
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
