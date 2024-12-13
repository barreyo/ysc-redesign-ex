defmodule Ysc.Events do
  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.Events.Event

  def subscribe() do
    Phoenix.PubSub.subscribe(Ysc.PubSub, topic())
  end

  @doc """
  Fetch an event by its ID.
  """
  def get_event!(id) do
    Repo.get!(Event, id) |> Repo.preload(:agendas)
  end

  @doc """
  Fetch an event by its reference ID.
  """
  def get_event_by_reference!(reference_id) do
    Repo.get_by!(Event, reference_id: reference_id)
  end

  @doc """
  List all events, optionally with filters.
  """
  def list_events(filters \\ %{}) do
    Event
    |> apply_filters(filters)
    |> Repo.all()
    |> Repo.preload(:organizer)
  end

  def list_events_paginated(params) do
    Event
    |> join(:left, [p], u in assoc(p, :organizer), as: :organizer)
    |> preload([organizer: p], organizer: p)
    |> Flop.validate_and_run(params, for: Event)
  end

  @doc """
  Insert a new event into the database.
  """
  def create_event(attrs \\ %{}) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, event} ->
        broadcast(%Ysc.MessagePassingEvents.EventAdded{event: event})
        {:ok, event}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Update an existing event with new attributes.
  """
  def update_event(%Event{} = event, attrs) do
    event
    |> Event.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, event} ->
        broadcast(%Ysc.MessagePassingEvents.EventUpdated{event: event})
        {:ok, event}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Delete an event from the database.
  """
  def delete_event(%Event{} = event) do
    Repo.delete(event)
  end

  @doc """
  Count the number of published events.
  """
  def count_published_events do
    Event
    |> where(state: "published")
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Fetch events with upcoming start dates, optionally limited.
  """
  def list_upcoming_events(limit \\ 50) do
    Event
    |> where([e], e.start_date > ^DateTime.utc_now())
    |> where([e], e.state in [:published])
    |> order_by(asc: :start_date)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Publish an event by updating its state and setting `published_at`.
  """
  def publish_event(%Event{} = event) do
    now = DateTime.utc_now()

    event
    |> Event.changeset(%{state: "published", published_at: now})
    |> Repo.update()
    |> case do
      {:ok, event} ->
        broadcast(%Ysc.MessagePassingEvents.EventUpdated{event: event})
        {:ok, event}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def unpublish_event(%Event{} = event) do
    event
    |> Event.changeset(%{state: "draft", published_at: nil})
    |> Repo.update()
    |> case do
      {:ok, event} ->
        broadcast(%Ysc.MessagePassingEvents.EventUpdated{event: event})
        {:ok, event}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def schedule_event(%Event{} = event, publish_at) do
    event
    |> Event.changeset(%{state: "scheduled", publish_at: publish_at})
    |> Repo.update()
    |> case do
      {:ok, event} ->
        broadcast(%Ysc.MessagePassingEvents.EventUpdated{event: event})
        {:ok, event}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def get_all_authors() do
    from(
      event in Event,
      left_join: user in assoc(event, :organizer),
      distinct: event.organizer_id,
      select: %{
        "organizer_id" => event.organizer_id,
        "organizer_first" => user.first_name,
        "organizer_last" => user.last_name
      },
      order_by: [{:desc, user.first_name}]
    )
    |> Repo.all()
    |> format_authors()
  end

  defp format_authors(result) do
    result
    |> Enum.reduce([], fn entry, acc ->
      [{name_format(entry), entry["organizer_id"]} | acc]
    end)
  end

  defp name_format(%{"organizer_first" => first, "organizer_last" => last}) do
    "#{String.capitalize(first)} #{String.downcase(last)}"
  end

  # Helper function for applying filters dynamically.
  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:organizer_id, organizer_id}, query -> where(query, [e], e.organizer_id == ^organizer_id)
      {:state, state}, query -> where(query, [e], e.state == ^state)
      {:title, title}, query -> where(query, [e], ilike(e.title, ^"%#{title}%"))
      _other, query -> query
    end)
  end

  defp topic() do
    "events"
  end

  defp broadcast(event) do
    Phoenix.PubSub.broadcast(Ysc.PubSub, topic(), {__MODULE__, event})
  end
end
