defmodule Ysc.Events do
  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.Events.Event
  alias Ysc.Events.TicketTier
  alias Ysc.Events.Ticket

  def subscribe() do
    Phoenix.PubSub.subscribe(Ysc.PubSub, topic())
  end

  @doc """
  Fetch an event by its ID.
  """
  def get_event!(id) do
    Repo.get!(Event, id)
  end

  @doc """
  Fetch an event by its ID, returns nil if not found.
  """
  def get_event(id) do
    Repo.get(Event, id)
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
    |> where([e], e.state not in ["deleted"])
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
    event
    |> Event.changeset(%{state: "deleted", published_at: nil})
    |> Repo.update()
    |> case do
      {:ok, event} ->
        broadcast(%Ysc.MessagePassingEvents.EventDeleted{event: event})
        {:ok, event}

      {:error, changeset} ->
        {:error, changeset}
    end
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
    three_days_ago = DateTime.add(DateTime.utc_now(), -3, :day)

    from(e in Event,
      where: e.start_date > ^DateTime.utc_now(),
      where: e.state in [:published, :cancelled],
      left_join: t in Ticket,
      on: t.event_id == e.id and t.status == :confirmed and t.inserted_at >= ^three_days_ago,
      group_by: e.id,
      select: %{
        id: e.id,
        reference_id: e.reference_id,
        state: e.state,
        published_at: e.published_at,
        publish_at: e.publish_at,
        organizer_id: e.organizer_id,
        title: e.title,
        description: e.description,
        max_attendees: e.max_attendees,
        age_restriction: e.age_restriction,
        show_participants: e.show_participants,
        raw_details: e.raw_details,
        rendered_details: e.rendered_details,
        image_id: e.image_id,
        start_date: e.start_date,
        start_time: e.start_time,
        end_date: e.end_date,
        end_time: e.end_time,
        location_name: e.location_name,
        address: e.address,
        latitude: e.latitude,
        longitude: e.longitude,
        place_id: e.place_id,
        lock_version: e.lock_version,
        inserted_at: e.inserted_at,
        updated_at: e.updated_at,
        recent_tickets_count: count(t.id),
        selling_fast: fragment("count(?) >= 10", t.id)
      },
      order_by: [
        # First sort by state: non-cancelled events first, cancelled events last
        asc: fragment("CASE WHEN ? = 'cancelled' THEN 1 ELSE 0 END", e.state),
        # Then sort by start_date for non-cancelled events
        asc: e.start_date,
        # Finally sort by start_time for events on the same date
        asc: e.start_time
      ],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.map(&add_pricing_info/1)
  end

  # Helper function to add pricing information to events
  defp add_pricing_info(event) do
    ticket_tiers = list_ticket_tiers_for_event(event.id)
    pricing_info = calculate_event_pricing(ticket_tiers)

    # Handle both structs and maps (from our custom query)
    case event do
      %{__struct__: _} -> Map.put(event, :pricing_info, pricing_info)
      %{} -> Map.put(event, :pricing_info, pricing_info)
    end
  end

  # Calculate pricing display information for an event
  defp calculate_event_pricing([]) do
    %{display_text: "FREE", has_free_tiers: true, lowest_price: nil}
  end

  defp calculate_event_pricing(ticket_tiers) do
    # Check if there are any free tiers (handle both atom and string types)
    has_free_tiers = Enum.any?(ticket_tiers, &(&1.type == :free or &1.type == "free"))

    # Get the lowest price from paid tiers (handle both atom and string types)
    paid_tiers = Enum.filter(ticket_tiers, &(&1.type in [:paid, :donation, "paid", "donation"]))

    case {has_free_tiers, paid_tiers} do
      {true, []} ->
        %{display_text: "FREE", has_free_tiers: true, lowest_price: nil}

      {true, _paid_tiers} ->
        # When there are both free and paid tiers, show "From $0.00"
        %{display_text: "From $0.00", has_free_tiers: true, lowest_price: nil}

      {false, []} ->
        %{display_text: "FREE", has_free_tiers: false, lowest_price: nil}

      {false, paid_tiers} ->
        lowest_price = Enum.min_by(paid_tiers, & &1.price.amount, fn -> nil end)

        # If there's only one paid tier, show the exact price instead of "From $X"
        display_text =
          if length(paid_tiers) == 1 do
            format_price(lowest_price.price)
          else
            "From #{format_price(lowest_price.price)}"
          end

        %{
          display_text: display_text,
          has_free_tiers: false,
          lowest_price: lowest_price
        }
    end
  end

  # Format price for display
  defp format_price(%Money{} = money) do
    Ysc.MoneyHelper.format_money!(money)
  end

  defp format_price(_), do: "$0.00"

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

  def cancel_event(%Event{} = event) do
    event
    |> Event.changeset(%{state: "cancelled"})
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

  # Ticket Tier Management Functions

  @doc """
  List all ticket tiers for an event with ticket counts.
  """
  def list_ticket_tiers_for_event(event_id) do
    from(tt in TicketTier,
      where: tt.event_id == ^event_id,
      left_join: t in Ticket,
      on: t.ticket_tier_id == tt.id and t.status == :confirmed,
      group_by: [
        tt.id,
        tt.name,
        tt.description,
        tt.type,
        tt.price,
        tt.quantity,
        tt.requires_registration,
        tt.start_date,
        tt.end_date,
        tt.event_id,
        tt.lock_version,
        tt.inserted_at,
        tt.updated_at
      ],
      select: %{
        id: tt.id,
        name: tt.name,
        description: tt.description,
        type: tt.type,
        price: tt.price,
        quantity: tt.quantity,
        requires_registration: tt.requires_registration,
        start_date: tt.start_date,
        end_date: tt.end_date,
        event_id: tt.event_id,
        lock_version: tt.lock_version,
        inserted_at: tt.inserted_at,
        updated_at: tt.updated_at,
        sold_tickets_count: count(t.id)
      },
      order_by: [asc: tt.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Get a ticket tier by ID.
  """
  def get_ticket_tier!(id) do
    Repo.get!(TicketTier, id)
  end

  @doc """
  Get a ticket tier by ID, returns nil if not found.
  """
  def get_ticket_tier(id) do
    Repo.get(TicketTier, id)
  end

  @doc """
  Create a new ticket tier.
  """
  def create_ticket_tier(attrs \\ %{}) do
    %TicketTier{}
    |> TicketTier.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, ticket_tier} ->
        broadcast(%Ysc.MessagePassingEvents.TicketTierAdded{ticket_tier: ticket_tier})
        {:ok, ticket_tier}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Update an existing ticket tier.
  """
  def update_ticket_tier(%TicketTier{} = ticket_tier, attrs) do
    ticket_tier
    |> TicketTier.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, ticket_tier} ->
        broadcast(%Ysc.MessagePassingEvents.TicketTierUpdated{ticket_tier: ticket_tier})
        {:ok, ticket_tier}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Delete a ticket tier.
  """
  def delete_ticket_tier(%TicketTier{} = ticket_tier) do
    Repo.delete(ticket_tier)
    |> case do
      {:ok, ticket_tier} ->
        broadcast(%Ysc.MessagePassingEvents.TicketTierDeleted{ticket_tier: ticket_tier})
        {:ok, ticket_tier}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Count the number of tickets sold for a specific ticket tier.
  """
  def count_tickets_for_tier(ticket_tier_id) do
    Ticket
    |> where([t], t.ticket_tier_id == ^ticket_tier_id and t.status == :confirmed)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Count the total number of tickets sold for an event across all ticket tiers.
  """
  def count_total_tickets_sold_for_event(event_id) do
    Ticket
    |> where([t], t.event_id == ^event_id and t.status == :confirmed)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Check if an event is selling fast based on recent ticket sales.

  An event is considered "selling fast" if it has sold 10 or more tickets
  in the last 3 days.

  ## Parameters:
  - `event_id`: The ID of the event to check

  ## Returns:
  - `true` if the event is selling fast
  - `false` otherwise
  """
  def is_event_selling_fast?(event_id) do
    three_days_ago = DateTime.add(DateTime.utc_now(), -3, :day)

    recent_ticket_count =
      Ticket
      |> where([t], t.event_id == ^event_id and t.status == :confirmed)
      |> where([t], t.inserted_at >= ^three_days_ago)
      |> Repo.aggregate(:count, :id)

    recent_ticket_count >= 10
  end

  @doc """
  Get the count of tickets sold in the last 3 days for an event.

  ## Parameters:
  - `event_id`: The ID of the event to check

  ## Returns:
  - Integer count of tickets sold in the last 3 days
  """
  def count_recent_tickets_sold(event_id) do
    three_days_ago = DateTime.add(DateTime.utc_now(), -3, :day)

    Ticket
    |> where([t], t.event_id == ^event_id and t.status == :confirmed)
    |> where([t], t.inserted_at >= ^three_days_ago)
    |> Repo.aggregate(:count, :id)
  end

  # Ticket Management Functions

  @doc """
  List all tickets for an event with user and ticket tier information.
  """
  def list_tickets_for_event(event_id) do
    Ticket
    |> where([t], t.event_id == ^event_id)
    |> join(:left, [t], tt in assoc(t, :ticket_tier), as: :ticket_tier)
    |> join(:left, [t], u in assoc(t, :user), as: :user)
    |> preload([ticket_tier: tt, user: u], ticket_tier: tt, user: u)
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
  end

  @doc """
  Get ticket purchase summary for an event.
  """
  def get_ticket_purchase_summary(event_id) do
    from(t in Ticket,
      where: t.event_id == ^event_id and t.status == :confirmed,
      join: tt in assoc(t, :ticket_tier),
      join: u in assoc(t, :user),
      group_by: [tt.id, tt.name, u.id, u.first_name, u.last_name, u.email, tt.price],
      select: %{
        ticket_tier_id: tt.id,
        ticket_tier_name: tt.name,
        user_id: u.id,
        user_name: fragment("? || ' ' || ?", u.first_name, u.last_name),
        user_email: u.email,
        ticket_count: count(t.id),
        ticket_tier_price: tt.price
      }
    )
    |> Repo.all()
    |> Enum.map(fn purchase ->
      # Calculate total amount by multiplying price by count
      total_amount =
        try do
          case purchase.ticket_tier_price do
            %Money{amount: amount} ->
              Money.new(Decimal.mult(amount, Decimal.new(purchase.ticket_count)), :USD)

            _ ->
              Money.new(0, :USD)
          end
        rescue
          _ ->
            Money.new(0, :USD)
        end

      purchase
      |> Map.put(:total_amount, total_amount)
      |> Map.delete(:ticket_tier_price)
    end)
  end

  @doc """
  Create a new ticket with validation.
  """
  def create_ticket(attrs \\ %{}) do
    %Ticket{}
    |> Ticket.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, ticket} ->
        broadcast(%Ysc.MessagePassingEvents.TicketCreated{ticket: ticket})
        {:ok, ticket}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  List all tickets for a specific user with event and ticket tier information.
  """
  def list_tickets_for_user(user_id) do
    Ticket
    |> where([t], t.user_id == ^user_id)
    |> join(:left, [t], e in assoc(t, :event), as: :event)
    |> join(:left, [t], tt in assoc(t, :ticket_tier), as: :ticket_tier)
    |> preload([event: e, ticket_tier: tt], event: e, ticket_tier: tt)
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
  end

  @doc """
  List upcoming events that a user has tickets for.
  """
  def list_upcoming_events_for_user(user_id) do
    Ticket
    |> where([t], t.user_id == ^user_id)
    |> join(:left, [t], e in assoc(t, :event), as: :event)
    |> join(:left, [t], tt in assoc(t, :ticket_tier), as: :ticket_tier)
    |> where([event: e], e.start_date > ^DateTime.utc_now())
    |> where([event: e], e.state in [:published, :cancelled])
    |> preload([event: e, ticket_tier: tt], event: e, ticket_tier: tt)
    |> order_by([event: e], asc: e.start_date)
    |> Repo.all()
  end

  defp broadcast(event) do
    Phoenix.PubSub.broadcast(Ysc.PubSub, topic(), {__MODULE__, event})
  end
end
