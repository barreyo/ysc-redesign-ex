defmodule YscWeb.Workers.EmailNotifier do
  @moduledoc """
  Oban worker for sending email notifications.

  Processes email templates and sends them to recipients asynchronously.
  """
  require Logger
  use Oban.Worker, queue: :mailers, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    template = get_in(job.args, ["template"])
    recipient = get_in(job.args, ["recipient"])

    # Log immediately - this should ALWAYS appear if the function is called
    Logger.info("EmailNotifier.perform called - JOB RECEIVED",
      job_id: job.id,
      worker: inspect(job.worker),
      queue: job.queue,
      template: template,
      recipient: recipient,
      state: job.state,
      attempt: job.attempt
    )

    case job.args do
      %{
        "recipient" => recipient,
        "idempotency_key" => idempotency_key,
        "subject" => subject,
        "template" => template,
        "params" => params,
        "text_body" => text_body,
        "user_id" => user_id
      } ->
        perform_with_args(
          job,
          recipient,
          idempotency_key,
          subject,
          template,
          params,
          text_body,
          user_id
        )

      args ->
        Logger.error("EmailNotifier job received invalid args",
          job_id: job.id,
          args: args,
          expected_keys: [
            "recipient",
            "idempotency_key",
            "subject",
            "template",
            "params",
            "text_body",
            "user_id"
          ]
        )

        {:error, "Invalid job args: missing required fields"}
    end
  end

  defp perform_with_args(
         job,
         recipient,
         idempotency_key,
         subject,
         template,
         params,
         text_body,
         user_id
       ) do
    Logger.info("EmailNotifier job started",
      job_id: job.id,
      recipient: recipient,
      idempotency_key: idempotency_key,
      subject: subject,
      template: template,
      user_id: user_id
    )

    try do
      template_module = YscWeb.Emails.Notifier.get_template_module(template)

      if template_module do
        Logger.info("Template module found: #{inspect(template_module)}")
      else
        Logger.error("Template module not found for template: #{template}")
        raise "Template module not found for template: #{template}"
      end

      atomized_params = atomize_keys(params)
      Logger.info("Atomized params: #{inspect(atomized_params)}")

      result =
        YscWeb.Emails.Notifier.send_email_idempotent(
          recipient,
          idempotency_key,
          subject,
          template_module,
          atomized_params,
          text_body,
          user_id
        )

      case result do
        {:ok, _email} ->
          Logger.info("Email sent successfully",
            job_id: job.id,
            recipient: recipient,
            idempotency_key: idempotency_key
          )

          :ok

        {:error, reason} ->
          Logger.error("Failed to send email",
            job_id: job.id,
            recipient: recipient,
            idempotency_key: idempotency_key,
            error: reason
          )

          {:error, reason}
      end
    rescue
      error ->
        Logger.error("EmailNotifier job failed",
          job_id: job.id,
          recipient: recipient,
          idempotency_key: idempotency_key,
          error: error,
          stacktrace: __STACKTRACE__
        )

        {:error, error}
    end
  end

  def atomize_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      {String.to_atom(key), atomize_keys(value)}
    end)
  end

  def atomize_keys(list) when is_list(list) do
    Enum.map(list, &atomize_keys/1)
  end

  def atomize_keys(other) do
    other
  end
end
