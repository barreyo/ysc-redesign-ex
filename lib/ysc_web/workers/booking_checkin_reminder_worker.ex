defmodule YscWeb.Workers.BookingCheckinReminderWorker do
  @moduledoc """
  Oban worker for sending booking check-in reminder emails.

  Sends an email 2 days before check-in with door code, location, and check-in information.
  """
  require Logger
  use Oban.Worker, queue: :mailers, max_attempts: 3

  alias Ysc.Repo
  alias Ysc.Bookings.Booking
  alias YscWeb.Emails.{Notifier, BookingCheckinReminder}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"booking_id" => booking_id}}) do
    Logger.info("Processing booking check-in reminder",
      booking_id: booking_id
    )

    case Repo.get(Booking, booking_id) |> Repo.preload([:user, :rooms]) do
      nil ->
        Logger.warning("Booking not found for check-in reminder",
          booking_id: booking_id
        )

        :ok

      booking ->
        # Only send if booking is still active (not cancelled or refunded)
        if booking.status in [:complete] do
          send_checkin_reminder_email(booking)
        else
          Logger.info("Booking is not active, skipping check-in reminder",
            booking_id: booking_id,
            status: booking.status
          )

          :ok
        end
    end
  end

  defp send_checkin_reminder_email(booking) do
    require Logger

    try do
      email_module = BookingCheckinReminder
      email_data = email_module.prepare_email_data(booking)
      subject = email_module.get_subject()
      template_name = email_module.get_template_name()

      # Generate idempotency key to prevent duplicate emails
      idempotency_key = "booking_checkin_reminder_#{booking.id}"

      Logger.info("Sending booking check-in reminder",
        booking_id: booking.id,
        user_id: booking.user_id,
        checkin_date: booking.checkin_date,
        property: booking.property
      )

      case Notifier.schedule_email(
             booking.user.email,
             idempotency_key,
             subject,
             template_name,
             email_data,
             "",
             booking.user_id
           ) do
        %Oban.Job{} ->
          Logger.info("Booking check-in reminder scheduled successfully",
            booking_id: booking.id
          )

          :ok

        {:error, reason} ->
          Logger.error("Failed to schedule booking check-in reminder",
            booking_id: booking.id,
            error: inspect(reason)
          )

          # Report to Sentry
          Sentry.capture_message("Failed to schedule booking check-in reminder",
            level: :error,
            extra: %{
              booking_id: booking.id,
              user_id: booking.user_id,
              error: inspect(reason)
            },
            tags: %{
              email_template: template_name,
              reminder_type: "checkin_reminder"
            }
          )

          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Failed to send booking check-in reminder",
          booking_id: booking.id,
          error: Exception.message(error),
          stacktrace: __STACKTRACE__
        )

        # Report to Sentry
        Sentry.capture_exception(error,
          stacktrace: __STACKTRACE__,
          extra: %{
            booking_id: booking.id,
            user_id: booking.user_id
          },
          tags: %{
            email_template: "booking_checkin_reminder",
            reminder_type: "checkin_reminder"
          }
        )

        {:error, error}
    end
  end

  @doc """
  Schedules a check-in reminder email for a booking.

  The email will be sent 3 days before the check-in date.
  If check-in is less than 3 days away, the email is sent immediately.
  """
  def schedule_reminder(booking_id, checkin_date) do
    require Logger

    # Calculate delay until 3 days before check-in
    now = DateTime.utc_now()
    checkin_datetime = DateTime.new!(checkin_date, ~T[00:00:00], "Etc/UTC")
    reminder_datetime = DateTime.add(checkin_datetime, -3, :day)

    # Calculate seconds until reminder should be sent
    delay_seconds = DateTime.diff(reminder_datetime, now, :second)

    if delay_seconds > 0 do
      # Schedule for 3 days before check-in
      %{
        "booking_id" => booking_id
      }
      |> new(schedule_in: delay_seconds)
      |> Oban.insert()

      Logger.info("Scheduled check-in reminder email",
        booking_id: booking_id,
        checkin_date: checkin_date,
        delay_days: delay_seconds / (24 * 60 * 60)
      )
    else
      # If check-in is less than 3 days away, send immediately
      Logger.info("Check-in is less than 3 days away, sending reminder immediately",
        booking_id: booking_id,
        checkin_date: checkin_date
      )

      # Load booking and send email immediately
      case Repo.get(Booking, booking_id) |> Repo.preload([:user, :rooms]) do
        nil ->
          Logger.warning("Booking not found for immediate check-in reminder",
            booking_id: booking_id
          )

          :ok

        booking ->
          # Only send if booking is still active
          if booking.status == :complete do
            send_checkin_reminder_email(booking)
          else
            Logger.info("Booking is not active, skipping immediate check-in reminder",
              booking_id: booking_id,
              status: booking.status
            )

            :ok
          end
      end
    end
  end
end
