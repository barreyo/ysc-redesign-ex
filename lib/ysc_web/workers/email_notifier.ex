defmodule YscWeb.Workers.EmailNotifier do
  require Logger
  use Oban.Worker, queue: :mailers, max_attempts: 3

  def perform(
        %Oban.Job{
          args:
            %{
              "recipient" => recipient,
              "idempotency_key" => idempotency_key,
              "subject" => subject,
              "template" => template,
              "params" => params,
              "text_body" => text_body,
              "user_id" => user_id
            } = _args
        } = job
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
