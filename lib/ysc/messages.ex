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
    Ecto.Multi.new()
    |> Ecto.Multi.insert(
      :message_idempotency,
      MessageIdempotency.changeset(%MessageIdempotency{}, attrs)
    )
    |> Ecto.Multi.run(:send_email, fn repo, result ->
      case Mailer.deliver(email) do
        {:ok, _metadata} ->
          {:ok, email}

        _ ->
          repo.rollback({:error, "failed to send email"})
          {:error, "failed to send email"}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{send_email: email}} ->
        {:ok, email}

      {:error, :message_idempotency, _, _} ->
        {:ok, email}

      _ ->
        {:error, "failed to send email"}
    end
  end
end
