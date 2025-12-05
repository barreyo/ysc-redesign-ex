defmodule Ysc.EventsTest do
  use Ysc.DataCase

  alias Ysc.Events
  alias Ysc.Events.Ticket
  import Ysc.AccountsFixtures

  describe "selling fast functionality" do
    test "is_event_selling_fast? returns true when 10+ tickets sold in last 3 days" do
      # Create a user and event
      user = user_fixture()

      # Create an event
      {:ok, event} =
        Events.create_event(%{
          title: "Test Event",
          description: "A test event",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 7, :day),
          published_at: DateTime.utc_now()
        })

      # Create a ticket tier for the tickets
      {:ok, ticket_tier} =
        Events.create_ticket_tier(%{
          name: "General Admission",
          type: :paid,
          price: Money.new(50, :USD),
          quantity: 100,
          event_id: event.id
        })

      # Create 10 tickets with recent timestamps (within last 3 days)
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      # 1 day ago
      recent_time = DateTime.add(now, -1, :day)

      # Insert 10 confirmed tickets with ticket_tier_id
      for _i <- 1..10 do
        %Ticket{
          id: Ecto.ULID.generate(),
          event_id: event.id,
          user_id: user.id,
          ticket_tier_id: ticket_tier.id,
          status: :confirmed,
          inserted_at: recent_time,
          expires_at: DateTime.add(DateTime.utc_now() |> DateTime.truncate(:second), 1, :day)
        }
        |> Repo.insert!()
      end

      # Test the function
      assert Events.event_selling_fast?(event.id) == true
    end

    test "is_event_selling_fast? returns false when less than 10 tickets sold in last 3 days" do
      # Create a user and event
      user = user_fixture()

      # Create an event
      {:ok, event} =
        Events.create_event(%{
          title: "Test Event 2",
          description: "A test event",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 7, :day),
          published_at: DateTime.utc_now()
        })

      # Create only 5 tickets with recent timestamps
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      # 1 day ago
      recent_time = DateTime.add(now, -1, :day)

      # Insert 5 confirmed tickets
      for _i <- 1..5 do
        %Ticket{
          id: Ecto.ULID.generate(),
          event_id: event.id,
          user_id: user.id,
          status: :confirmed,
          inserted_at: recent_time,
          expires_at: DateTime.add(DateTime.utc_now() |> DateTime.truncate(:second), 1, :day)
        }
        |> Repo.insert!()
      end

      # Test the function
      assert Events.event_selling_fast?(event.id) == false
    end

    test "is_event_selling_fast? returns false when tickets are older than 3 days" do
      # Create a user and event
      user = user_fixture()

      # Create an event
      {:ok, event} =
        Events.create_event(%{
          title: "Test Event 3",
          description: "A test event",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 7, :day),
          published_at: DateTime.utc_now()
        })

      # Create 15 tickets with old timestamps (more than 3 days ago)
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      # 5 days ago
      old_time = DateTime.add(now, -5, :day)

      # Insert 15 confirmed tickets
      for _i <- 1..15 do
        %Ticket{
          id: Ecto.ULID.generate(),
          event_id: event.id,
          user_id: user.id,
          status: :confirmed,
          inserted_at: old_time,
          expires_at: DateTime.add(DateTime.utc_now() |> DateTime.truncate(:second), 1, :day)
        }
        |> Repo.insert!()
      end

      # Test the function
      assert Events.event_selling_fast?(event.id) == false
    end

    test "count_recent_tickets_sold returns correct count" do
      # Create a user and event
      user = user_fixture()

      # Create an event
      {:ok, event} =
        Events.create_event(%{
          title: "Test Event 4",
          description: "A test event",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 7, :day),
          published_at: DateTime.utc_now()
        })

      # Create tickets with different timestamps
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      # 1 day ago
      recent_time = DateTime.add(now, -1, :day)
      # 5 days ago
      old_time = DateTime.add(now, -5, :day)

      # Insert 3 recent confirmed tickets
      for _i <- 1..3 do
        %Ticket{
          id: Ecto.ULID.generate(),
          event_id: event.id,
          user_id: user.id,
          status: :confirmed,
          inserted_at: recent_time,
          expires_at: DateTime.add(DateTime.utc_now() |> DateTime.truncate(:second), 1, :day)
        }
        |> Repo.insert!()
      end

      # Insert 2 old confirmed tickets
      for _i <- 1..2 do
        %Ticket{
          id: Ecto.ULID.generate(),
          event_id: event.id,
          user_id: user.id,
          status: :confirmed,
          inserted_at: old_time,
          expires_at: DateTime.add(DateTime.utc_now() |> DateTime.truncate(:second), 1, :day)
        }
        |> Repo.insert!()
      end

      # Insert 1 pending ticket (should not be counted)
      %Ticket{
        id: Ecto.ULID.generate(),
        event_id: event.id,
        user_id: user.id,
        status: :pending,
        inserted_at: recent_time,
        expires_at: DateTime.add(DateTime.utc_now() |> DateTime.truncate(:second), 1, :day)
      }
      |> Repo.insert!()

      # Test the function
      assert Events.count_recent_tickets_sold(event.id) == 3
    end
  end
end
