defmodule DuplicateWebhookEventError do
  defexception message: "Webhook event already exists"
end

defmodule Ysc.Webhooks do
  alias Ysc.Webhooks.WebhookEvent
  alias Ysc.Repo
  import Ecto.Query

  @doc """
  Creates a webhook event, raising an error if a duplicate event exists.
  The error can be caught and handled by the caller.
  """
  def create_webhook_event!(attrs) do
    %WebhookEvent{}
    |> WebhookEvent.changeset(attrs)
    |> Repo.insert!()
  rescue
    Ecto.ConstraintError ->
      raise DuplicateWebhookEventError, "Webhook event already exists"
  end

  @doc """
  Locks a webhook event for processing. Returns {:ok, webhook_event} if successful,
  {:error, :not_found} if the event doesn't exist, or {:error, :already_processing}
  if the event is already being processed.
  """
  def lock_webhook_event(event_id) do
    # Use FOR UPDATE SKIP LOCKED to handle concurrent processing attempts
    query =
      from(w in WebhookEvent,
        where: w.id == ^event_id and w.state == :pending,
        lock: "FOR UPDATE SKIP LOCKED"
      )

    case Repo.one(query) do
      nil ->
        case Repo.get(WebhookEvent, event_id) do
          nil -> {:error, :not_found}
          %WebhookEvent{state: state} when state != :pending -> {:error, :already_processing}
        end

      webhook_event ->
        {:ok, _updated} =
          webhook_event
          |> Ecto.Changeset.change(%{state: :processing})
          |> Repo.update()

        {:ok, webhook_event}
    end
  end

  @doc """
  Gets and locks a webhook event by ID until processed.
  Returns {:ok, webhook_event} if found and locked, {:error, :not_found} otherwise.
  """
  def get_and_lock_webhook(id) do
    query =
      from(w in WebhookEvent,
        where: w.id == ^id,
        lock: "FOR UPDATE SKIP LOCKED"
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      webhook -> {:ok, webhook}
    end
  end

  @doc """
  Updates the state of a webhook event.
  Returns {:ok, webhook_event} if successful, {:error, changeset} if validation fails.
  """
  def update_webhook_state(webhook, state) do
    webhook
    |> Ecto.Changeset.change(%{state: state})
    |> Repo.update()
  end

  @doc """
  Lists all unprocessed webhook event IDs (those in pending state).
  Returns a list of webhook event IDs.
  """
  def list_unprocessed_webhook_ids do
    WebhookEvent
    |> where([w], w.state == :pending)
    |> select([w], w.id)
    |> Repo.all()
  end

  @doc """
  Updates a webhook event's state to complete or failed.
  Returns {:ok, webhook_event} if successful, or {:error, :not_found} if not found.
  """
  def update_webhook_event_state(event_id, new_state) when new_state in [:complete, :failed] do
    case Repo.get(WebhookEvent, event_id) do
      nil ->
        {:error, :not_found}

      webhook_event ->
        webhook_event
        |> Ecto.Changeset.change(%{state: new_state})
        |> Repo.update()
    end
  end

  @doc """
  Lists pending webhook events.
  Optional limit parameter to control the number of events returned.
  """
  def list_pending_webhook_events(limit \\ 100) do
    WebhookEvent
    |> where([w], w.state == :pending)
    |> order_by([w], asc: w.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets a webhook event by ID.
  Returns nil if not found.
  """
  def get_webhook_event(event_id) do
    Repo.get(WebhookEvent, event_id)
  end
end
