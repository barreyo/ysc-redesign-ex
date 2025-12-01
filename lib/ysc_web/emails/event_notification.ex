defmodule YscWeb.Emails.EventNotification do
  @moduledoc """
  Email template for event notifications.

  Sent to users 1 hour after an event is published (if event is still published).
  """
  use MjmlEEx,
    mjml_template: "templates/event_notification.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  alias Ysc.Repo
  alias Ysc.Events.Event

  def get_template_name() do
    "event_notification"
  end

  def get_subject(event \\ nil) do
    if event do
      "New Event: #{event.title}"
    else
      "New Event"
    end
  end

  def event_url(event_id) do
    YscWeb.Endpoint.url() <> "/events/#{event_id}"
  end

  @doc """
  Prepares event notification email data.

  ## Parameters:
  - `event`: The event that was published
  - `user`: The user to send the notification to

  ## Returns:
  - Map with all necessary data for the email template
  """
  def prepare_email_data(event, user) do
    # Validate input
    if is_nil(event) do
      raise ArgumentError, "Event cannot be nil"
    end

    if is_nil(user) do
      raise ArgumentError, "User cannot be nil"
    end

    # Ensure event is loaded with necessary associations
    event =
      if Ecto.assoc_loaded?(event.organizer) do
        event
      else
        case Repo.get(Event, event.id) |> Repo.preload([:organizer]) do
          nil ->
            raise ArgumentError, "Event not found: #{event.id}"

          loaded_event ->
            loaded_event
        end
      end

    # Format event date and time
    event_date_time = format_event_datetime(event)

    %{
      first_name: user.first_name || "Valued Member",
      event: event,
      event_date_time: event_date_time,
      event_url: event_url(event.id)
    }
  end

  defp format_event_datetime(event) do
    case {event.start_date, event.start_time} do
      {nil, _} ->
        nil

      {date, nil} ->
        # Convert DateTime to Date if needed
        date_only = if is_struct(date, DateTime), do: DateTime.to_date(date), else: date
        Calendar.strftime(date_only, "%B %d, %Y")

      {date, time} ->
        # Convert DateTime to Date if needed
        date_only = if is_struct(date, DateTime), do: DateTime.to_date(date), else: date
        datetime = DateTime.new!(date_only, time, "Etc/UTC")
        # Convert to PST
        pst_datetime = DateTime.shift_zone!(datetime, "America/Los_Angeles")
        Calendar.strftime(pst_datetime, "%B %d, %Y at %I:%M %p %Z")
    end
  end
end
