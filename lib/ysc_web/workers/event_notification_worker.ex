defmodule YscWeb.Workers.EventNotificationWorker do
  @moduledoc """
  Oban worker for sending event notification emails.

  Sends emails to all users with event notifications enabled when an event is published.
  """
  require Logger
  use Oban.Worker, queue: :mailers, max_attempts: 3

  alias Ysc.Repo
  alias Ysc.Events.Event
  alias Ysc.Accounts.User
  alias YscWeb.Emails.{Notifier, EventNotification}
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_id" => event_id}}) do
    Logger.info("Processing event notification",
      event_id: event_id
    )

    case Repo.get(Event, event_id) |> Repo.preload([:organizer]) do
      nil ->
        Logger.warning("Event not found for notification",
          event_id: event_id
        )

        :ok

      event ->
        # Only send if event is still published
        if event.state == "published" or event.state == :published do
          send_event_notifications(event)
        else
          Logger.info("Event is no longer published, skipping notifications",
            event_id: event_id,
            state: event.state
          )

          :ok
        end
    end
  end

  @doc """
  Send event notification emails immediately to all users with event notifications enabled.
  """
  def send_event_notifications(event) do
    require Logger

    try do
      # Get all users with event notifications enabled
      users =
        from(u in User,
          where: u.event_notifications == true,
          where: not is_nil(u.confirmed_at),
          where: u.state == :active
        )
        |> Repo.all()

      Logger.info("Sending event notifications",
        event_id: event.id,
        event_title: event.title,
        user_count: length(users)
      )

      # Send email to each user
      results =
        Enum.map(users, fn user ->
          send_event_notification_email(event, user)
        end)

      # Count successes and failures
      success_count = Enum.count(results, &match?({:ok, _}, &1))
      failure_count = length(results) - success_count

      Logger.info("Event notifications sent",
        event_id: event.id,
        success_count: success_count,
        failure_count: failure_count
      )

      :ok
    rescue
      error ->
        Logger.error("Failed to send event notifications",
          event_id: event.id,
          error: Exception.message(error),
          stacktrace: __STACKTRACE__
        )

        # Report to Sentry
        Sentry.capture_exception(error,
          stacktrace: __STACKTRACE__,
          extra: %{
            event_id: event.id,
            event_title: event.title
          },
          tags: %{
            email_template: "event_notification",
            notification_type: "event_notification"
          }
        )

        {:error, error}
    end
  end

  defp send_event_notification_email(event, user) do
    require Logger

    try do
      email_module = EventNotification
      email_data = email_module.prepare_email_data(event, user)
      subject = email_module.get_subject(event)
      template_name = email_module.get_template_name()

      # Generate idempotency key to prevent duplicate emails
      idempotency_key = "event_notification_#{event.id}_#{user.id}"

      case Notifier.schedule_email(
             user.email,
             idempotency_key,
             subject,
             template_name,
             email_data,
             "",
             user.id
           ) do
        %Oban.Job{} ->
          Logger.debug("Event notification scheduled successfully",
            event_id: event.id,
            user_id: user.id
          )

          {:ok, :scheduled}

        {:error, reason} ->
          Logger.error("Failed to schedule event notification",
            event_id: event.id,
            user_id: user.id,
            error: inspect(reason)
          )

          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Failed to send event notification",
          event_id: event.id,
          user_id: user.id,
          error: Exception.message(error)
        )

        {:error, error}
    end
  end

  @doc """
  Schedules event notification emails for all users with event notifications enabled.

  The emails will be sent 1 hour after the event is published.
  """
  def schedule_notifications(event_id, published_at) do
    require Logger

    # Calculate 1 hour after publish time
    notification_datetime = DateTime.add(published_at, 3600, :second)

    now = DateTime.utc_now()

    # Check if the scheduled time is in the future
    if DateTime.compare(notification_datetime, now) == :gt do
      # Schedule for 1 hour after publish
      %{
        "event_id" => event_id
      }
      |> new(scheduled_at: notification_datetime)
      |> Oban.insert()

      Logger.info("Scheduled event notification emails",
        event_id: event_id,
        published_at: published_at,
        scheduled_at: notification_datetime
      )
    else
      # If 1 hour has already passed, send immediately
      Logger.info("1 hour has already passed since publish, sending notifications immediately",
        event_id: event_id,
        published_at: published_at
      )

      # Load event and send emails immediately
      case Repo.get(Event, event_id) |> Repo.preload([:organizer]) do
        nil ->
          Logger.warning("Event not found for immediate notification",
            event_id: event_id
          )

          :ok

        event ->
          # Only send if event is still published
          if event.state == "published" or event.state == :published do
            send_event_notifications(event)
          else
            Logger.info("Event is not published, skipping immediate notification",
              event_id: event_id,
              state: event.state
            )

            :ok
          end
      end
    end
  end
end
