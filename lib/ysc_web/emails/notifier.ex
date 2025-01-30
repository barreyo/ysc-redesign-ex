defmodule YscWeb.Emails.Notifier do
  import Swoosh.Email

  alias Ysc.Mailer

  @from_email "info@ysc.org"
  @from_name "YSC"

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
      |> html_body(attrs.rendered_message)
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
end
