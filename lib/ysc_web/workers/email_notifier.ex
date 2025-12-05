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
        "user_id" => user_id,
        "category" => category
      } ->
        perform_with_args(
          job,
          recipient,
          idempotency_key,
          subject,
          template,
          params,
          text_body,
          user_id,
          category
        )

      args ->
        # Try to handle legacy jobs without category
        case args do
          %{
            "recipient" => recipient,
            "idempotency_key" => idempotency_key,
            "subject" => subject,
            "template" => template,
            "params" => params,
            "text_body" => text_body,
            "user_id" => user_id
          } ->
            # Legacy job - get category from template
            category = Ysc.Accounts.EmailCategories.get_category(template)

            perform_with_args(
              job,
              recipient,
              idempotency_key,
              subject,
              template,
              params,
              text_body,
              user_id,
              category
            )

          _ ->
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
                "user_id",
                "category"
              ]
            )

            {:error, "Invalid job args: missing required fields"}
        end
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
         user_id,
         category
       ) do
    Logger.info("EmailNotifier job started",
      job_id: job.id,
      recipient: recipient,
      idempotency_key: idempotency_key,
      subject: subject,
      template: template,
      user_id: user_id,
      category: category
    )

    # Check user notification preferences if user_id is provided
    {should_send, final_user_id} =
      if user_id do
        case Ysc.Repo.get(Ysc.Accounts.User, user_id) do
          nil ->
            Logger.warning("User not found for email notification",
              user_id: user_id,
              template: template
            )

            {true, nil}

          user ->
            should_send = Ysc.Accounts.EmailCategories.should_send_email?(user, template)

            if not should_send do
              Logger.info("Email skipped due to user notification preferences",
                user_id: user_id,
                template: template,
                category: category,
                recipient: recipient
              )
            end

            {should_send, user_id}
        end
      else
        # No user_id - send email (e.g., board notifications)
        {true, nil}
      end

    if not should_send do
      Logger.info("Email notification skipped",
        job_id: job.id,
        user_id: user_id,
        template: template,
        category: category
      )

      :ok
    else
      try do
        template_module = YscWeb.Emails.Notifier.get_template_module(template)

        if template_module do
          Logger.info("Template module found: #{inspect(template_module)}")
        else
          error_message = "Template module not found for template: #{template}"

          Logger.error("Template module not found for template: #{template}")

          # Report to Sentry
          Sentry.capture_message(error_message,
            level: :error,
            extra: %{
              job_id: job.id,
              recipient: recipient,
              idempotency_key: idempotency_key,
              template: template,
              subject: subject,
              user_id: user_id,
              category: category
            },
            tags: %{
              email_template: template,
              email_category: to_string(category),
              has_user_id: !is_nil(user_id),
              error_type: "missing_template_module"
            }
          )

          raise error_message
        end

        atomized_params = atomize_keys(params)
        Logger.info("Atomized params: #{inspect(atomized_params)}")

        # Normalize recipient to ensure it's a string (Swoosh can handle tuples/lists, but we want consistency)
        normalized_recipient = normalize_recipient(recipient)

        result =
          YscWeb.Emails.Notifier.send_email_idempotent(
            normalized_recipient,
            idempotency_key,
            subject,
            template_module,
            atomized_params,
            text_body,
            final_user_id
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

            # Report to Sentry with context
            Sentry.capture_message("Email sending failed",
              level: :error,
              extra: %{
                job_id: job.id,
                recipient: recipient,
                idempotency_key: idempotency_key,
                template: template,
                subject: subject,
                user_id: user_id,
                category: category,
                error: inspect(reason)
              },
              tags: %{
                email_template: template,
                email_category: to_string(category),
                has_user_id: !is_nil(user_id)
              }
            )

            {:error, reason}
        end
      rescue
        error ->
          Logger.error("EmailNotifier job failed",
            job_id: job.id,
            recipient: recipient,
            idempotency_key: idempotency_key,
            template: template,
            error: inspect(error),
            error_type: inspect(error.__struct__),
            error_message: Exception.message(error),
            stacktrace: Exception.format_stacktrace(__STACKTRACE__)
          )

          # Report exception to Sentry with full context
          Sentry.capture_exception(error,
            stacktrace: __STACKTRACE__,
            extra: %{
              job_id: job.id,
              recipient: recipient,
              idempotency_key: idempotency_key,
              template: template,
              subject: subject,
              user_id: user_id,
              category: category,
              error_type: inspect(error.__struct__),
              error_message: Exception.message(error)
            },
            tags: %{
              email_template: template,
              email_category: to_string(category),
              has_user_id: !is_nil(user_id),
              worker: "EmailNotifier"
            }
          )

          {:error, error}
      end
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

  # Normalize recipient to a string format
  # Handles cases where recipient might be a list, tuple, or other format
  defp normalize_recipient(recipient) when is_binary(recipient) do
    recipient
  end

  defp normalize_recipient({_name, email}) when is_binary(email) do
    email
  end

  defp normalize_recipient([{_name, email} | _]) when is_binary(email) do
    email
  end

  defp normalize_recipient([email | _]) when is_binary(email) do
    email
  end

  defp normalize_recipient(recipient) do
    # Fallback: use inspect to safely convert any format to string
    # This handles edge cases where recipient might be in an unexpected format
    require Logger

    Logger.warning("Unexpected recipient format, normalizing",
      recipient: inspect(recipient),
      recipient_type: inspect(recipient.__struct__ || :no_struct)
    )

    # Try to extract email from various formats
    case recipient do
      list when is_list(list) ->
        # Try to extract email from list
        case List.first(list) do
          {_name, email} when is_binary(email) -> email
          email when is_binary(email) -> email
          _ -> inspect(recipient)
        end

      _ ->
        inspect(recipient)
    end
  end
end
