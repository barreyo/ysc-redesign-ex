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
end
