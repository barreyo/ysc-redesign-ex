defmodule Ysc.Messages do
  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.Messages.MessageIdempotency

  alias Ysc.Mailer

  def create_message_idempotency(attrs) do
    %MessageIdempotency{}
    |> MessageIdempotency.changeset(attrs)
    |> Repo.insert()
  end

  def run_send_message_idempotent(email, attrs) do
    require Logger

    Logger.debug("run_send_message_idempotent called",
      recipient: email.to,
      idempotency_key: attrs[:idempotency_key],
      message_template: attrs[:message_template]
    )

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

        {:ok, email}

      {:error, :message_idempotency, changeset, _} ->
        Logger.info("Duplicate message detected (idempotency), treating as success",
          recipient: email.to,
          idempotency_key: attrs[:idempotency_key],
          errors: inspect(changeset.errors)
        )

        {:ok, email}

      {:error, operation, reason, _changes} ->
        Logger.error("Email transaction failed",
          recipient: email.to,
          idempotency_key: attrs[:idempotency_key],
          operation: operation,
          reason: inspect(reason)
        )

        {:error, "failed to send email"}

      error ->
        Logger.error("Email transaction failed with unexpected error",
          recipient: email.to,
          idempotency_key: attrs[:idempotency_key],
          error: inspect(error)
        )

        {:error, "failed to send email"}
    end
  end
end
