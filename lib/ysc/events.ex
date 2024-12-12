defmodule Ysc.Events do
  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.Events.Event

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
  end

  @doc """
  Insert a new event into the database.
  """
  def create_event(attrs \\ %{}) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update an existing event with new attributes.
  """
  def update_event(%Event{} = event, attrs) do
    event
    |> Event.changeset(attrs)
    |> Repo.update()
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
  def list_upcoming_events(limit \\ 10) do
    Event
    |> where([e], e.start > ^DateTime.utc_now())
    |> order_by(asc: :start)
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
end
