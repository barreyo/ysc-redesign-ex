defmodule YscWeb.Workers.SmsNotifier do
  @moduledoc """
  Oban worker for sending SMS notifications.

  Processes SMS templates and sends them to recipients asynchronously.
  """
  require Logger
  use Oban.Worker, queue: :mailers, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    template = get_in(job.args, ["template"])
    phone_number = get_in(job.args, ["phone_number"])

    # Log immediately - this should ALWAYS appear if the function is called
    Logger.info("SmsNotifier.perform called - JOB RECEIVED",
      job_id: job.id,
      worker: inspect(job.worker),
      queue: job.queue,
      template: template,
      phone_number: phone_number,
      state: job.state,
      attempt: job.attempt
    )

    case job.args do
      %{
        "phone_number" => phone_number,
        "idempotency_key" => idempotency_key,
        "template" => template,
        "params" => params,
        "user_id" => user_id,
        "category" => category
      } ->
        perform_with_args(
          job,
          phone_number,
          idempotency_key,
          template,
          params,
          user_id,
          category
        )

      args ->
        # Try to handle legacy jobs without category
        case args do
          %{
            "phone_number" => phone_number,
            "idempotency_key" => idempotency_key,
            "template" => template,
            "params" => params,
            "user_id" => user_id
          } ->
            # Legacy job - get category from template
            category = Ysc.Accounts.SmsCategories.get_category(template)

            perform_with_args(
              job,
              phone_number,
              idempotency_key,
              template,
              params,
              user_id,
              category
            )

          _ ->
            Logger.error("SmsNotifier job received invalid args",
              job_id: job.id,
              args: args,
              expected_keys: [
                "phone_number",
                "idempotency_key",
                "template",
                "params",
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
         phone_number,
         idempotency_key,
         template,
         params,
         user_id,
         category
       ) do
    # Check user preferences if user_id is provided
    if user_id do
      case Ysc.Accounts.get_user(user_id) do
        nil ->
          Logger.warning("SMS sent without user validation - user not found",
            job_id: job.id,
            user_id: user_id,
            template: template
          )

          send_sms(job, phone_number, idempotency_key, template, params, user_id, category)

        user ->
          unless Ysc.Accounts.SmsCategories.should_send_sms?(user, template) do
            Logger.info("SMS not sent - user has disabled notifications",
              job_id: job.id,
              user_id: user_id,
              template: template,
              category: category
            )

            :ok
          else
            unless Ysc.Accounts.SmsCategories.has_phone_number?(user) do
              Logger.info("SMS not sent - user has no phone number",
                job_id: job.id,
                user_id: user_id,
                template: template
              )

              :ok
            else
              # Use user's phone number if different
              final_phone_number = phone_number || user.phone_number

              send_sms(
                job,
                final_phone_number,
                idempotency_key,
                template,
                params,
                user_id,
                category
              )
            end
          end
      end
    else
      send_sms(job, phone_number, idempotency_key, template, params, user_id, category)
    end
  end

  defp send_sms(job, phone_number, idempotency_key, template, params, user_id, category) do
    try do
      template_module = YscWeb.Sms.Notifier.get_template_module(template)

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
            phone_number: phone_number,
            idempotency_key: idempotency_key,
            template: template,
            user_id: user_id,
            category: category
          },
          tags: %{
            sms_template: template,
            sms_category: to_string(category),
            has_user_id: !is_nil(user_id),
            error_type: "missing_template_module"
          }
        )

        raise error_message
      end

      atomized_params = atomize_keys(params)
      Logger.info("Atomized params: #{inspect(atomized_params)}")

      result =
        YscWeb.Sms.Notifier.send_sms_idempotent(
          phone_number,
          idempotency_key,
          template,
          atomized_params,
          user_id
        )

      case result do
        {:ok, %{id: message_id}} ->
          Logger.info("SMS sent successfully",
            job_id: job.id,
            phone_number: phone_number,
            template: template,
            message_id: message_id,
            idempotency_key: idempotency_key
          )

          :ok

        {:error, reason} ->
          Logger.error("Failed to send SMS",
            job_id: job.id,
            phone_number: phone_number,
            template: template,
            idempotency_key: idempotency_key,
            reason: inspect(reason)
          )

          # Report to Sentry
          Sentry.capture_message("Failed to send SMS",
            level: :error,
            extra: %{
              job_id: job.id,
              phone_number: phone_number,
              idempotency_key: idempotency_key,
              template: template,
              user_id: user_id,
              category: category,
              reason: inspect(reason, limit: :infinity)
            },
            tags: %{
              sms_template: template,
              sms_category: to_string(category),
              error_type: "sms_send_failed",
              has_user_id: !is_nil(user_id)
            }
          )

          {:error, reason}
      end
    rescue
      error ->
        Logger.error("SmsNotifier raised exception",
          job_id: job.id,
          phone_number: phone_number,
          template: template,
          error: inspect(error),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )

        # Report exception to Sentry
        Sentry.capture_exception(error,
          stacktrace: __STACKTRACE__,
          extra: %{
            job_id: job.id,
            phone_number: phone_number,
            idempotency_key: idempotency_key,
            template: template,
            user_id: user_id,
            category: category,
            error_type: inspect(error.__struct__),
            error_message: Exception.message(error)
          },
          tags: %{
            sms_template: template,
            sms_category: to_string(category),
            error_type: "sms_notifier_exception",
            has_user_id: !is_nil(user_id)
          }
        )

        {:error, Exception.message(error)}
    end
  end

  # Helper function to convert string keys to atoms
  defp atomize_keys(params) when is_map(params) do
    Enum.reduce(params, %{}, fn
      {key, value} when is_binary(key) ->
        atom_key = String.to_existing_atom(key)
        {atom_key, atomize_keys(value)}

      {key, value} ->
        {key, atomize_keys(value)}
    end)
  end

  defp atomize_keys(value) when is_list(value) do
    Enum.map(value, &atomize_keys/1)
  end

  defp atomize_keys(value), do: value
end
