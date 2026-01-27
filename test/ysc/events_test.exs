defmodule Ysc.EventsTest do
  use Ysc.DataCase

  alias Ysc.Events
  alias Ysc.Events.Ticket
  import Ysc.AccountsFixtures

  setup do
    user = user_fixture()
    %{user: user}
  end

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

  describe "event CRUD operations" do
    test "create_event/1 creates an event", %{user: user} do
      attrs = %{
        title: "New Event",
        description: "Event description",
        state: :published,
        organizer_id: user.id,
        start_date: DateTime.add(DateTime.utc_now(), 30, :day),
        published_at: DateTime.utc_now()
      }

      assert {:ok, %Ysc.Events.Event{} = event} = Events.create_event(attrs)
      assert event.title == "New Event"
      assert event.organizer_id == user.id
    end

    test "update_event/2 updates an event", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Original Title",
          description: "Description",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now()
        })

      assert {:ok, updated} = Events.update_event(event, %{title: "Updated Title"})
      assert updated.title == "Updated Title"
    end

    test "delete_event/1 marks event as deleted", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "To Delete",
          description: "Description",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now()
        })

      assert {:ok, deleted} = Events.delete_event(event)
      assert deleted.state == :deleted
    end
  end

  describe "ticket tier management" do
    test "create_ticket_tier/1 creates a tier", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Event with Tiers",
          description: "Description",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now()
        })

      attrs = %{
        name: "VIP Tier",
        type: :paid,
        price: Money.new(100, :USD),
        quantity: 50,
        event_id: event.id
      }

      assert {:ok, %Ysc.Events.TicketTier{} = tier} = Events.create_ticket_tier(attrs)
      assert tier.name == "VIP Tier"
      assert tier.event_id == event.id
    end

    test "update_ticket_tier/2 updates a tier", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Event",
          description: "Description",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now()
        })

      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "Original Tier",
          type: :paid,
          price: Money.new(50, :USD),
          quantity: 100,
          event_id: event.id
        })

      assert {:ok, updated} = Events.update_ticket_tier(tier, %{name: "Updated Tier"})
      assert updated.name == "Updated Tier"
    end

    test "delete_ticket_tier/1 deletes a tier", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Event",
          description: "Description",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now()
        })

      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "To Delete",
          type: :paid,
          price: Money.new(50, :USD),
          quantity: 100,
          event_id: event.id
        })

      assert {:ok, _deleted} = Events.delete_ticket_tier(tier)
      assert Events.get_ticket_tier(tier.id) == nil
    end
  end

  describe "ticket counting" do
    test "count_tickets_for_tier/1 returns correct count", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Event",
          description: "Description",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now()
        })

      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "Tier",
          type: :paid,
          price: Money.new(50, :USD),
          quantity: 100,
          event_id: event.id
        })

      # Create some tickets
      for _i <- 1..5 do
        %Ysc.Events.Ticket{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: user.id,
          status: :confirmed
        }
        |> Ysc.Repo.insert!()
      end

      count = Events.count_tickets_for_tier(tier.id)
      assert count == 5
    end

    test "count_total_tickets_sold_for_event/1 returns correct count", %{user: user} do
      {:ok, event} =
        Events.create_event(%{
          title: "Event",
          description: "Description",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now()
        })

      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "Tier",
          type: :paid,
          price: Money.new(50, :USD),
          quantity: 100,
          event_id: event.id
        })

      # Create some tickets
      for _i <- 1..3 do
        %Ysc.Events.Ticket{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: user.id,
          status: :confirmed
        }
        |> Ysc.Repo.insert!()
      end

      count = Events.count_total_tickets_sold_for_event(event.id)
      assert count == 3
    end
  end
end
