defmodule Ysc.Messages do
  @moduledoc """
  Context module for managing messages and idempotency.

  Handles creation and tracking of messages with idempotency guarantees.
  """
  require Logger
  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.Messages.MessageIdempotency

  alias Ysc.Mailer
  alias Ysc.Flowroute.Client

  # Helper function to safely convert email recipient to string
  defp email_recipient_to_string(recipient) when is_binary(recipient), do: recipient
  defp email_recipient_to_string({_name, email}) when is_binary(email), do: email
  defp email_recipient_to_string([recipient | _]), do: email_recipient_to_string(recipient)
  defp email_recipient_to_string(other), do: inspect(other)

  def create_message_idempotency(attrs) do
    %MessageIdempotency{}
    |> MessageIdempotency.changeset(attrs)
    |> Repo.insert()
  end

  def run_send_message_idempotent(email, attrs) do
    Logger.debug("run_send_message_idempotent called",
      recipient: email.to,
      idempotency_key: attrs[:idempotency_key],
      message_template: attrs[:message_template]
    )

    try do
      result =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(
          :message_idempotency,
          MessageIdempotency.changeset(%MessageIdempotency{}, attrs)
        )
        |> Ecto.Multi.run(:send_email, fn repo, _result ->
          Logger.debug("Sending email via Mailer.deliver",
            recipient: email.to,
            idempotency_key: attrs[:idempotency_key]
          )

          case Mailer.deliver(email) do
            {:ok, _metadata} ->
              Logger.debug("Mailer.deliver succeeded",
                recipient: email.to,
                idempotency_key: attrs[:idempotency_key]
              )

              {:ok, email}

            error ->
              Logger.error("Mailer.deliver failed",
                recipient: email.to,
                idempotency_key: attrs[:idempotency_key],
                error: inspect(error)
              )

              # Report to Sentry with detailed context
              Sentry.capture_message("Mailer.deliver failed",
                level: :error,
                extra: %{
                  recipient: email_recipient_to_string(email.to),
                  idempotency_key: attrs[:idempotency_key],
                  message_template: attrs[:message_template],
                  user_id: attrs[:user_id],
                  email_subject: email.subject,
                  error: inspect(error, limit: :infinity)
                },
                tags: %{
                  email_template: attrs[:message_template] || "unknown",
                  error_type: "mailer_deliver_failed",
                  has_user_id: !is_nil(attrs[:user_id])
                }
              )

              repo.rollback({:error, "failed to send email"})
              {:error, "failed to send email"}
          end
        end)
        |> Repo.transaction()

      case result do
        {:ok, %{send_email: email}} ->
          Logger.debug("Email transaction succeeded",
            recipient: email.to,
            idempotency_key: attrs[:idempotency_key]
          )

          # Emit telemetry event for successful email send
          :telemetry.execute(
            [:ysc, :email, :sent],
            %{count: 1},
            %{
              template: attrs[:message_template] || "unknown",
              recipient: email_recipient_to_string(email.to),
              idempotency_key: attrs[:idempotency_key] || nil
            }
          )

          {:ok, email}

        {:error, :message_idempotency, changeset, _} ->
          Logger.info("Duplicate message detected (idempotency), treating as success",
            recipient: email.to,
            idempotency_key: attrs[:idempotency_key],
            errors: inspect(changeset.errors)
          )

          # Emit telemetry event for duplicate email (idempotency - treat as success)
          :telemetry.execute(
            [:ysc, :email, :sent],
            %{count: 1},
            %{
              template: attrs[:message_template] || "unknown",
              recipient: email_recipient_to_string(email.to),
              idempotency_key: attrs[:idempotency_key] || nil,
              duplicate: true
            }
          )

          {:ok, email}

        {:error, operation, reason, _changes} ->
          Logger.error("Email transaction failed",
            recipient: email.to,
            idempotency_key: attrs[:idempotency_key],
            operation: operation,
            reason: inspect(reason)
          )

          # Report to Sentry with detailed context
          Sentry.capture_message("Email transaction failed",
            level: :error,
            extra: %{
              recipient: email_recipient_to_string(email.to),
              idempotency_key: attrs[:idempotency_key],
              message_template: attrs[:message_template],
              user_id: attrs[:user_id],
              email_subject: email.subject,
              operation: to_string(operation),
              reason: inspect(reason, limit: :infinity)
            },
            tags: %{
              email_template: attrs[:message_template] || "unknown",
              error_type: "email_transaction_failed",
              operation: to_string(operation),
              has_user_id: !is_nil(attrs[:user_id])
            }
          )

          # Emit telemetry event for email send failure
          :telemetry.execute(
            [:ysc, :email, :send_failed],
            %{count: 1},
            %{
              template: attrs[:message_template] || "unknown",
              recipient: email_recipient_to_string(email.to),
              idempotency_key: attrs[:idempotency_key] || nil,
              operation: to_string(operation),
              reason: inspect(reason)
            }
          )

          {:error, "failed to send email"}

        error ->
          Logger.error("Email transaction failed with unexpected error",
            recipient: email.to,
            idempotency_key: attrs[:idempotency_key],
            error: inspect(error)
          )

          # Report to Sentry with detailed context
          Sentry.capture_message("Email transaction failed with unexpected error",
            level: :error,
            extra: %{
              recipient: email_recipient_to_string(email.to),
              idempotency_key: attrs[:idempotency_key],
              message_template: attrs[:message_template],
              user_id: attrs[:user_id],
              email_subject: email.subject,
              error: inspect(error, limit: :infinity)
            },
            tags: %{
              email_template: attrs[:message_template] || "unknown",
              error_type: "email_transaction_unexpected_error",
              has_user_id: !is_nil(attrs[:user_id])
            }
          )

          # Emit telemetry event for email send failure
          :telemetry.execute(
            [:ysc, :email, :send_failed],
            %{count: 1},
            %{
              template: attrs[:message_template] || "unknown",
              recipient: email_recipient_to_string(email.to),
              idempotency_key: attrs[:idempotency_key] || nil,
              error: inspect(error)
            }
          )

          {:error, "failed to send email"}
      end
    rescue
      error in [Ecto.ConstraintError] ->
        # Check if this is the idempotency constraint violation
        if error.type == :unique do
          # Normalize constraint name to string for comparison
          constraint_string = to_string(error.constraint)

          idempotency_constraint_names = [
            "message_idempotency_entries_unique_index",
            "message_idempotency_entries_message_type_idempotency_key_messag"
          ]

          if constraint_string in idempotency_constraint_names do
            Logger.info(
              "Duplicate message detected (idempotency constraint), treating as success",
              recipient: email.to,
              idempotency_key: attrs[:idempotency_key],
              constraint: constraint_string
            )

            # Emit telemetry event for duplicate email (idempotency - treat as success)
            :telemetry.execute(
              [:ysc, :email, :sent],
              %{count: 1},
              %{
                template: attrs[:message_template] || "unknown",
                recipient: email_recipient_to_string(email.to),
                idempotency_key: attrs[:idempotency_key] || nil,
                duplicate: true
              }
            )

            {:ok, email}
          else
            Logger.error("Email transaction raised unique constraint error (not idempotency)",
              recipient: email.to,
              idempotency_key: attrs[:idempotency_key],
              constraint: constraint_string,
              error: inspect(error)
            )

            # Report to Sentry with detailed context
            Sentry.capture_exception(error,
              extra: %{
                recipient: email_recipient_to_string(email.to),
                idempotency_key: attrs[:idempotency_key],
                message_template: attrs[:message_template],
                user_id: attrs[:user_id],
                email_subject: email.subject,
                constraint: constraint_string,
                constraint_type: error.type
              },
              tags: %{
                email_template: attrs[:message_template] || "unknown",
                error_type: "unique_constraint_error",
                constraint: constraint_string,
                has_user_id: !is_nil(attrs[:user_id])
              }
            )

            # Emit telemetry event for email send failure
            :telemetry.execute(
              [:ysc, :email, :send_failed],
              %{count: 1},
              %{
                template: attrs[:message_template] || "unknown",
                recipient: email_recipient_to_string(email.to),
                idempotency_key: attrs[:idempotency_key] || nil,
                constraint: constraint_string,
                error: inspect(error)
              }
            )

            {:error, "failed to send email"}
          end
        else
          Logger.error("Email transaction raised constraint error (not unique)",
            recipient: email.to,
            idempotency_key: attrs[:idempotency_key],
            constraint: error.constraint,
            type: error.type,
            error: inspect(error)
          )

          # Report to Sentry with detailed context
          Sentry.capture_exception(error,
            extra: %{
              recipient: email_recipient_to_string(email.to),
              idempotency_key: attrs[:idempotency_key],
              message_template: attrs[:message_template],
              user_id: attrs[:user_id],
              email_subject: email.subject,
              constraint: to_string(error.constraint),
              constraint_type: error.type
            },
            tags: %{
              email_template: attrs[:message_template] || "unknown",
              error_type: "constraint_error",
              constraint: to_string(error.constraint),
              has_user_id: !is_nil(attrs[:user_id])
            }
          )

          # Emit telemetry event for email send failure
          :telemetry.execute(
            [:ysc, :email, :send_failed],
            %{count: 1},
            %{
              template: attrs[:message_template] || "unknown",
              recipient: email_recipient_to_string(email.to),
              idempotency_key: attrs[:idempotency_key] || nil,
              constraint: to_string(error.constraint),
              error: inspect(error)
            }
          )

          {:error, "failed to send email"}
        end

      error ->
        Logger.error("Email transaction raised exception",
          recipient: email.to,
          idempotency_key: attrs[:idempotency_key],
          error: inspect(error),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )

        # Report exception to Sentry with full context
        Sentry.capture_exception(error,
          stacktrace: __STACKTRACE__,
          extra: %{
            recipient: email_recipient_to_string(email.to),
            idempotency_key: attrs[:idempotency_key],
            message_template: attrs[:message_template],
            user_id: attrs[:user_id],
            email_subject: email.subject,
            error_type: inspect(error.__struct__),
            error_message: Exception.message(error)
          },
          tags: %{
            email_template: attrs[:message_template] || "unknown",
            error_type: "email_transaction_exception",
            has_user_id: !is_nil(attrs[:user_id])
          }
        )

        # Emit telemetry event for email send failure
        :telemetry.execute(
          [:ysc, :email, :send_failed],
          %{count: 1},
          %{
            template: attrs[:message_template] || "unknown",
            recipient: email_recipient_to_string(email.to),
            idempotency_key: attrs[:idempotency_key] || nil,
            error: inspect(error)
          }
        )

        {:error, "failed to send email"}
    end
  end

  @doc """
  Lists all messages (notifications) for a user, ordered by most recent first.
  """
  def list_user_messages(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    from(m in MessageIdempotency,
      where: m.user_id == ^user_id,
      order_by: [desc: m.id],
      limit: ^limit,
      offset: ^offset
    )
    |> Repo.all()
  end

  @doc """
  Gets the total count of messages for a user.
  """
  def count_user_messages(user_id) do
    from(m in MessageIdempotency,
      where: m.user_id == ^user_id,
      select: count()
    )
    |> Repo.one()
  end

  @doc """
  Sends an SMS message with idempotency handling.

  This function ensures that duplicate SMS messages are not sent by using
  the message idempotency system. If a message with the same idempotency key
  and template has already been sent, it will be treated as a success.

  ## Parameters

    - `phone_number` (required) - Recipient phone number in 11-digit North American format
    - `body` (required) - Message content
    - `attrs` (required) - Map containing:
      - `:idempotency_key` (required) - Unique key for idempotency
      - `:message_template` (required) - Template identifier
      - `:user_id` (optional) - User ID if associated with a user
      - `:params` (optional) - Additional parameters
      - `:from` (optional) - Sender phone number (defaults to configured FlowRoute number)

  ## Returns

    - `{:ok, %{id: message_id}}` - Success with FlowRoute message ID
    - `{:error, reason}` - Error with reason

  ## Examples

      {:ok, %{id: "mdr2-..."}} =
        Ysc.Messages.run_send_sms_idempotent(
          "12065551234",
          "Your booking confirmation",
          idempotency_key: "booking_123",
          message_template: "booking_confirmation",
          user_id: user.id,
          params: %{booking_id: 123}
        )
  """
  @spec run_send_sms_idempotent(String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def run_send_sms_idempotent(phone_number, body, attrs) do
    Logger.debug("run_send_sms_idempotent called",
      recipient: phone_number,
      idempotency_key: attrs[:idempotency_key],
      message_template: attrs[:message_template]
    )

    try do
      result =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(
          :message_idempotency,
          MessageIdempotency.changeset(%MessageIdempotency{}, %{
            message_type: "sms",
            idempotency_key: attrs[:idempotency_key],
            message_template: attrs[:message_template],
            phone_number: phone_number,
            user_id: attrs[:user_id],
            params: attrs[:params],
            rendered_message: body
          })
        )
        |> Ecto.Multi.run(:send_sms, fn _repo, _result ->
          Logger.debug("Sending SMS via FlowRoute Client",
            recipient: phone_number,
            idempotency_key: attrs[:idempotency_key]
          )

          sms_opts = [
            to: phone_number,
            body: body
          ]

          sms_opts =
            if attrs[:from] do
              Keyword.put(sms_opts, :from, attrs[:from])
            else
              sms_opts
            end

          case Client.send_sms(sms_opts) do
            {:ok, %{id: message_id}} = result ->
              Logger.debug("FlowRoute Client.send_sms succeeded",
                recipient: phone_number,
                idempotency_key: attrs[:idempotency_key],
                message_id: message_id
              )

              result

            error ->
              Logger.error("FlowRoute Client.send_sms failed",
                recipient: phone_number,
                idempotency_key: attrs[:idempotency_key],
                error: inspect(error)
              )

              # Report to Sentry with detailed context
              Sentry.capture_message("FlowRoute Client.send_sms failed",
                level: :error,
                extra: %{
                  recipient: phone_number,
                  idempotency_key: attrs[:idempotency_key],
                  message_template: attrs[:message_template],
                  user_id: attrs[:user_id],
                  message_body: body,
                  error: inspect(error, limit: :infinity)
                },
                tags: %{
                  sms_template: attrs[:message_template] || "unknown",
                  error_type: "flowroute_send_sms_failed",
                  has_user_id: !is_nil(attrs[:user_id])
                }
              )

              {:error, "failed to send SMS"}
          end
        end)
        |> Repo.transaction()

      case result do
        {:ok, %{send_sms: %{id: message_id}}} ->
          Logger.debug("SMS transaction succeeded",
            recipient: phone_number,
            idempotency_key: attrs[:idempotency_key],
            message_id: message_id
          )

          # Emit telemetry event for successful SMS send
          :telemetry.execute(
            [:ysc, :sms, :sent],
            %{count: 1},
            %{
              template: attrs[:message_template] || "unknown",
              recipient: phone_number,
              idempotency_key: attrs[:idempotency_key] || nil,
              message_id: message_id
            }
          )

          {:ok, %{id: message_id}}

        {:error, :message_idempotency, changeset, _} ->
          Logger.info("Duplicate SMS detected (idempotency), treating as success",
            recipient: phone_number,
            idempotency_key: attrs[:idempotency_key],
            errors: inspect(changeset.errors)
          )

          # Emit telemetry event for duplicate SMS (idempotency - treat as success)
          :telemetry.execute(
            [:ysc, :sms, :sent],
            %{count: 1},
            %{
              template: attrs[:message_template] || "unknown",
              recipient: phone_number,
              idempotency_key: attrs[:idempotency_key] || nil,
              duplicate: true
            }
          )

          # Return a fake success response for idempotency
          {:ok, %{id: "mdr2-idempotent"}}

        {:error, operation, reason, _changes} ->
          Logger.error("SMS transaction failed",
            recipient: phone_number,
            idempotency_key: attrs[:idempotency_key],
            operation: operation,
            reason: inspect(reason)
          )

          # Report to Sentry with detailed context
          Sentry.capture_message("SMS transaction failed",
            level: :error,
            extra: %{
              recipient: phone_number,
              idempotency_key: attrs[:idempotency_key],
              message_template: attrs[:message_template],
              user_id: attrs[:user_id],
              message_body: body,
              operation: to_string(operation),
              reason: inspect(reason, limit: :infinity)
            },
            tags: %{
              sms_template: attrs[:message_template] || "unknown",
              error_type: "sms_transaction_failed",
              operation: to_string(operation),
              has_user_id: !is_nil(attrs[:user_id])
            }
          )

          # Emit telemetry event for SMS send failure
          :telemetry.execute(
            [:ysc, :sms, :send_failed],
            %{count: 1},
            %{
              template: attrs[:message_template] || "unknown",
              recipient: phone_number,
              idempotency_key: attrs[:idempotency_key] || nil,
              operation: to_string(operation),
              reason: inspect(reason)
            }
          )

          {:error, "failed to send SMS"}

        error ->
          Logger.error("SMS transaction failed with unexpected error",
            recipient: phone_number,
            idempotency_key: attrs[:idempotency_key],
            error: inspect(error)
          )

          # Report to Sentry with detailed context
          Sentry.capture_message("SMS transaction failed with unexpected error",
            level: :error,
            extra: %{
              recipient: phone_number,
              idempotency_key: attrs[:idempotency_key],
              message_template: attrs[:message_template],
              user_id: attrs[:user_id],
              message_body: body,
              error: inspect(error, limit: :infinity)
            },
            tags: %{
              sms_template: attrs[:message_template] || "unknown",
              error_type: "sms_transaction_unexpected_error",
              has_user_id: !is_nil(attrs[:user_id])
            }
          )

          # Emit telemetry event for SMS send failure
          :telemetry.execute(
            [:ysc, :sms, :send_failed],
            %{count: 1},
            %{
              template: attrs[:message_template] || "unknown",
              recipient: phone_number,
              idempotency_key: attrs[:idempotency_key] || nil,
              error: inspect(error)
            }
          )

          {:error, "failed to send SMS"}
      end
    rescue
      error in [Ecto.ConstraintError] ->
        # Check if this is the idempotency constraint violation
        if error.type == :unique do
          # Normalize constraint name to string for comparison
          constraint_string = to_string(error.constraint)

          idempotency_constraint_names = [
            "message_idempotency_entries_unique_index",
            "message_idempotency_entries_message_type_idempotency_key_messag"
          ]

          if constraint_string in idempotency_constraint_names do
            Logger.info(
              "Duplicate SMS detected (idempotency constraint), treating as success",
              recipient: phone_number,
              idempotency_key: attrs[:idempotency_key],
              constraint: constraint_string
            )

            # Emit telemetry event for duplicate SMS (idempotency - treat as success)
            :telemetry.execute(
              [:ysc, :sms, :sent],
              %{count: 1},
              %{
                template: attrs[:message_template] || "unknown",
                recipient: phone_number,
                idempotency_key: attrs[:idempotency_key] || nil,
                duplicate: true
              }
            )

            {:ok, %{id: "mdr2-idempotent"}}
          else
            Logger.error("SMS transaction raised unique constraint error (not idempotency)",
              recipient: phone_number,
              idempotency_key: attrs[:idempotency_key],
              constraint: constraint_string,
              error: inspect(error)
            )

            # Report to Sentry with detailed context
            Sentry.capture_exception(error,
              extra: %{
                recipient: phone_number,
                idempotency_key: attrs[:idempotency_key],
                message_template: attrs[:message_template],
                user_id: attrs[:user_id],
                message_body: body,
                constraint: constraint_string,
                constraint_type: error.type
              },
              tags: %{
                sms_template: attrs[:message_template] || "unknown",
                error_type: "unique_constraint_error",
                constraint: constraint_string,
                has_user_id: !is_nil(attrs[:user_id])
              }
            )

            # Emit telemetry event for SMS send failure
            :telemetry.execute(
              [:ysc, :sms, :send_failed],
              %{count: 1},
              %{
                template: attrs[:message_template] || "unknown",
                recipient: phone_number,
                idempotency_key: attrs[:idempotency_key] || nil,
                constraint: constraint_string,
                error: inspect(error)
              }
            )

            {:error, "failed to send SMS"}
          end
        else
          Logger.error("SMS transaction raised constraint error (not unique)",
            recipient: phone_number,
            idempotency_key: attrs[:idempotency_key],
            constraint: error.constraint,
            type: error.type,
            error: inspect(error)
          )

          # Report to Sentry with detailed context
          Sentry.capture_exception(error,
            extra: %{
              recipient: phone_number,
              idempotency_key: attrs[:idempotency_key],
              message_template: attrs[:message_template],
              user_id: attrs[:user_id],
              message_body: body,
              constraint: to_string(error.constraint),
              constraint_type: error.type
            },
            tags: %{
              sms_template: attrs[:message_template] || "unknown",
              error_type: "constraint_error",
              constraint: to_string(error.constraint),
              has_user_id: !is_nil(attrs[:user_id])
            }
          )

          # Emit telemetry event for SMS send failure
          :telemetry.execute(
            [:ysc, :sms, :send_failed],
            %{count: 1},
            %{
              template: attrs[:message_template] || "unknown",
              recipient: phone_number,
              idempotency_key: attrs[:idempotency_key] || nil,
              constraint: to_string(error.constraint),
              error: inspect(error)
            }
          )

          {:error, "failed to send SMS"}
        end

      error ->
        Logger.error("SMS transaction raised exception",
          recipient: phone_number,
          idempotency_key: attrs[:idempotency_key],
          error: inspect(error),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )

        # Report exception to Sentry with full context
        Sentry.capture_exception(error,
          stacktrace: __STACKTRACE__,
          extra: %{
            recipient: phone_number,
            idempotency_key: attrs[:idempotency_key],
            message_template: attrs[:message_template],
            user_id: attrs[:user_id],
            message_body: body,
            error_type: inspect(error.__struct__),
            error_message: Exception.message(error)
          },
          tags: %{
            sms_template: attrs[:message_template] || "unknown",
            error_type: "sms_transaction_exception",
            has_user_id: !is_nil(attrs[:user_id])
          }
        )

        # Emit telemetry event for SMS send failure
        :telemetry.execute(
          [:ysc, :sms, :send_failed],
          %{count: 1},
          %{
            template: attrs[:message_template] || "unknown",
            recipient: phone_number,
            idempotency_key: attrs[:idempotency_key] || nil,
            error: inspect(error)
          }
        )

        {:error, "failed to send SMS"}
    end
  end
end
