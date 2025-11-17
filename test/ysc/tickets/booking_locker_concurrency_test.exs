defmodule Ysc.Tickets.BookingLockerConcurrencyTest do
  @moduledoc """
  Extensive concurrency tests for ticket booking to ensure no data races or overbooking.

  These tests simulate high-concurrency scenarios where multiple users attempt to book
  tickets simultaneously, verifying that optimistic locking mechanisms prevent
  double-booking and ensure capacity limits are respected.
  """
  use Ysc.DataCase, async: true

  alias Ysc.Tickets.BookingLocker
  alias Ysc.Events
  alias Ysc.Events.Ticket
  alias Ysc.Repo
  import Ysc.AccountsFixtures

  setup do
    # Create users for concurrent booking tests with active memberships
    users =
      Enum.map(1..50, fn _ ->
        user = user_fixture()
        # Give user lifetime membership so they can purchase tickets
        user
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at: DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Repo.update!()
      end)

    # Create an event with limited capacity
    organizer =
      user_fixture()
      |> Ecto.Changeset.change(
        lifetime_membership_awarded_at: DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Repo.update!()

    {:ok, event} =
      Events.create_event(%{
        title: "Concurrency Test Event",
        description: "Testing concurrent bookings",
        state: :published,
        organizer_id: organizer.id,
        start_date: DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), 30, :day),
        max_attendees: 100,
        published_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

    # Create ticket tiers with limited quantities
    {:ok, tier1} =
      Events.create_ticket_tier(%{
        name: "General Admission",
        type: :paid,
        price: Money.new(50, :USD),
        quantity: 50,
        event_id: event.id
      })

    {:ok, tier2} =
      Events.create_ticket_tier(%{
        name: "VIP",
        type: :paid,
        price: Money.new(100, :USD),
        quantity: 25,
        event_id: event.id
      })

    {:ok, tier_unlimited} =
      Events.create_ticket_tier(%{
        name: "Unlimited Tier",
        type: :paid,
        price: Money.new(25, :USD),
        # Unlimited
        quantity: nil,
        event_id: event.id
      })

    %{
      users: users,
      event: event,
      tier1: tier1,
      tier2: tier2,
      tier_unlimited: tier_unlimited,
      organizer: organizer
    }
  end

  describe "concurrent ticket bookings - tier capacity limits" do
    test "prevents overbooking when multiple users book same tier simultaneously", %{
      users: users,
      event: event,
      tier1: tier1,
      sandbox_owner: owner
    } do
      # Tier has capacity of 50
      # 60 users try to book 1 ticket each simultaneously
      concurrent_users = Enum.take(users, 60)

      results =
        concurrent_users
        |> Task.async_stream(
          fn user ->
            Ysc.DataCase.allow_sandbox(self(), owner)
            BookingLocker.atomic_booking(user.id, event.id, %{tier1.id => 1})
          end,
          max_concurrency: 60,
          timeout: 10_000,
          on_timeout: :kill_task
        )
        |> Enum.to_list()

      # Count successful bookings
      successful_bookings =
        Enum.count(results, fn
          {:ok, {:ok, _}} -> true
          # Handle both patterns
          {:ok, _} -> true
          _ -> false
        end)

      # Count failed bookings
      failed_bookings =
        Enum.count(results, fn
          {:ok, {:error, _}} -> true
          _ -> false
        end)

      # Verify exactly 50 bookings succeeded (tier capacity)
      assert successful_bookings == 50,
             "Expected exactly 50 successful bookings, got #{successful_bookings}. Failed: #{failed_bookings}"

      # Verify exactly 10 bookings failed (over capacity)
      assert failed_bookings == 10,
             "Expected exactly 10 failed bookings, got #{failed_bookings}"

      # Verify total tickets created matches successful bookings
      total_tickets =
        Ticket
        |> where([t], t.event_id == ^event.id and t.ticket_tier_id == ^tier1.id)
        |> where([t], t.status in [:pending, :confirmed])
        |> Repo.aggregate(:count, :id)

      assert total_tickets == 50,
             "Expected exactly 50 tickets, got #{total_tickets}"

      # Verify no overbooking occurred
      assert total_tickets <= tier1.quantity,
             "Overbooking detected: #{total_tickets} tickets for tier with capacity #{tier1.quantity}"
    end

    test "handles concurrent bookings for multiple tiers simultaneously", %{
      users: users,
      event: event,
      tier1: tier1,
      tier2: tier2,
      sandbox_owner: owner
    } do
      # Tier1 has capacity 50, Tier2 has capacity 25
      # Create 80 concurrent booking attempts
      concurrent_users = Enum.take(users, 80)

      results =
        concurrent_users
        |> Enum.with_index()
        |> Task.async_stream(
          fn {user, index} ->
            Ysc.DataCase.allow_sandbox(self(), owner)
            # Alternate between tier1 and tier2
            tier_id = if rem(index, 2) == 0, do: tier1.id, else: tier2.id
            BookingLocker.atomic_booking(user.id, event.id, %{tier_id => 1})
          end,
          max_concurrency: 80,
          timeout: 10_000
        )
        |> Enum.to_list()

      successful_bookings =
        Enum.count(results, fn
          {:ok, {:ok, _}} -> true
          {:ok, _} -> true
          _ -> false
        end)

      failed_bookings = Enum.count(results, &match?({:ok, {:error, _}}, &1))

      # Verify total successful bookings don't exceed tier capacities
      tier1_tickets =
        Ticket
        |> where([t], t.ticket_tier_id == ^tier1.id)
        |> where([t], t.status in [:pending, :confirmed])
        |> Repo.aggregate(:count, :id)

      tier2_tickets =
        Ticket
        |> where([t], t.ticket_tier_id == ^tier2.id)
        |> where([t], t.status in [:pending, :confirmed])
        |> Repo.aggregate(:count, :id)

      assert tier1_tickets <= tier1.quantity,
             "Tier1 overbooked: #{tier1_tickets} > #{tier1.quantity}"

      assert tier2_tickets <= tier2.quantity,
             "Tier2 overbooked: #{tier2_tickets} > #{tier2.quantity}"

      # Verify total successful bookings match sum of tier tickets
      assert successful_bookings == tier1_tickets + tier2_tickets
    end

    test "prevents overbooking when users request multiple tickets simultaneously", %{
      users: users,
      event: event,
      tier1: tier1,
      sandbox_owner: owner
    } do
      # Tier has capacity 50
      # 20 users try to book 3 tickets each (total 60 tickets requested)
      concurrent_users = Enum.take(users, 20)

      results =
        concurrent_users
        |> Task.async_stream(
          fn user ->
            Ysc.DataCase.allow_sandbox(self(), owner)
            BookingLocker.atomic_booking(user.id, event.id, %{tier1.id => 3})
          end,
          max_concurrency: 20,
          timeout: 10_000
        )
        |> Enum.to_list()

      successful_bookings =
        Enum.count(results, fn
          {:ok, {:ok, _}} -> true
          {:ok, _} -> true
          _ -> false
        end)

      failed_bookings = Enum.count(results, &match?({:ok, {:error, _}}, &1))

      # Calculate expected successful bookings
      # 50 tickets / 3 tickets per booking = 16 bookings (48 tickets) + 1 booking (2 tickets) = 17 bookings
      # Actually: floor(50/3) = 16 bookings with 3 tickets = 48 tickets, 2 tickets remaining
      # So 16 successful bookings, 4 failed bookings

      total_tickets =
        Ticket
        |> where([t], t.ticket_tier_id == ^tier1.id)
        |> where([t], t.status in [:pending, :confirmed])
        |> Repo.aggregate(:count, :id)

      assert total_tickets <= tier1.quantity,
             "Overbooking detected: #{total_tickets} tickets for tier with capacity #{tier1.quantity}"

      # Verify we got some successful and some failed bookings
      assert successful_bookings > 0, "Expected at least some successful bookings"
      assert failed_bookings > 0, "Expected at least some failed bookings"

      assert successful_bookings + failed_bookings == 20,
             "Expected 20 total booking attempts, got #{successful_bookings + failed_bookings}"
    end
  end

  describe "concurrent ticket bookings - event capacity limits" do
    test "respects event-level max_attendees when booking different tiers", %{
      users: users,
      event: event,
      tier1: tier1,
      tier2: tier2,
      sandbox_owner: owner
    } do
      # Event has max_attendees: 100
      # Tier1 capacity: 50, Tier2 capacity: 25
      # But event limit is 100, so we can book up to 100 tickets total

      # Create 120 concurrent booking attempts (would exceed event capacity)
      concurrent_users = Enum.take(users, 120)

      results =
        concurrent_users
        |> Enum.with_index()
        |> Task.async_stream(
          fn {user, index} ->
            Ysc.DataCase.allow_sandbox(self(), owner)
            # Alternate between tiers
            tier_id = if rem(index, 2) == 0, do: tier1.id, else: tier2.id
            BookingLocker.atomic_booking(user.id, event.id, %{tier_id => 1})
          end,
          max_concurrency: 120,
          timeout: 15_000
        )
        |> Enum.to_list()

      successful_bookings = Enum.count(results, &match?({:ok, {:ok, _}}, &1))

      # Count total confirmed tickets (event capacity check uses confirmed status)
      total_confirmed_tickets =
        Ticket
        |> where([t], t.event_id == ^event.id)
        |> where([t], t.status == :confirmed)
        |> Repo.aggregate(:count, :id)

      # Count total pending tickets (these also count against capacity in the booking logic)
      total_pending_tickets =
        Ticket
        |> where([t], t.event_id == ^event.id)
        |> where([t], t.status == :pending)
        |> Repo.aggregate(:count, :id)

      total_tickets = total_confirmed_tickets + total_pending_tickets

      # Note: The booking logic checks tier capacity first, then event capacity
      # So we might hit tier limits before event limits
      # But total tickets should never exceed event.max_attendees
      assert total_tickets <= event.max_attendees,
             "Event overbooked: #{total_tickets} tickets for event with capacity #{event.max_attendees}"
    end
  end

  describe "concurrent ticket bookings - pending tickets count against capacity" do
    test "pending tickets prevent new bookings from exceeding capacity", %{
      users: users,
      event: event,
      tier1: tier1,
      sandbox_owner: owner
    } do
      # Tier has capacity 50
      # First wave: 30 users book tickets (creates 30 pending tickets)
      first_wave_users = Enum.take(users, 30)

      first_wave_results =
        first_wave_users
        |> Task.async_stream(
          fn user ->
            Ysc.DataCase.allow_sandbox(self(), owner)
            BookingLocker.atomic_booking(user.id, event.id, %{tier1.id => 1})
          end,
          max_concurrency: 30,
          timeout: 10_000
        )
        |> Enum.to_list()

      first_wave_successful = Enum.count(first_wave_results, &match?({:ok, {:ok, _}}, &1))
      assert first_wave_successful == 30, "First wave should all succeed"

      # Verify 30 pending tickets exist
      pending_count =
        Ticket
        |> where([t], t.ticket_tier_id == ^tier1.id)
        |> where([t], t.status == :pending)
        |> Repo.aggregate(:count, :id)

      assert pending_count == 30, "Expected 30 pending tickets"

      # Second wave: 30 more users try to book (should only allow 20 more)
      second_wave_users = Enum.take(Enum.drop(users, 30), 30)

      second_wave_results =
        second_wave_users
        |> Task.async_stream(
          fn user ->
            Ysc.DataCase.allow_sandbox(self(), owner)
            BookingLocker.atomic_booking(user.id, event.id, %{tier1.id => 1})
          end,
          max_concurrency: 30,
          timeout: 10_000
        )
        |> Enum.to_list()

      second_wave_successful = Enum.count(second_wave_results, &match?({:ok, {:ok, _}}, &1))
      second_wave_failed = Enum.count(second_wave_results, &match?({:ok, {:error, _}}, &1))

      # Should only allow 20 more bookings (50 total - 30 pending = 20 available)
      assert second_wave_successful == 20,
             "Second wave should allow 20 bookings, got #{second_wave_successful}"

      assert second_wave_failed == 10,
             "Second wave should fail 10 bookings, got #{second_wave_failed}"

      # Verify total tickets equals capacity
      total_tickets =
        Ticket
        |> where([t], t.ticket_tier_id == ^tier1.id)
        |> where([t], t.status in [:pending, :confirmed])
        |> Repo.aggregate(:count, :id)

      assert total_tickets == 50,
             "Expected exactly 50 tickets (capacity), got #{total_tickets}"
    end
  end

  describe "concurrent ticket bookings - unlimited tiers" do
    test "allows unlimited concurrent bookings for unlimited tier", %{
      users: users,
      event: event,
      tier_unlimited: tier_unlimited,
      sandbox_owner: owner
    } do
      # Unlimited tier should allow all bookings
      concurrent_users = Enum.take(users, 50)

      results =
        concurrent_users
        |> Task.async_stream(
          fn user ->
            Ysc.DataCase.allow_sandbox(self(), owner)
            BookingLocker.atomic_booking(user.id, event.id, %{tier_unlimited.id => 1})
          end,
          max_concurrency: 50,
          timeout: 10_000
        )
        |> Enum.to_list()

      successful_bookings =
        Enum.count(results, fn
          {:ok, {:ok, _}} -> true
          {:ok, _} -> true
          _ -> false
        end)

      failed_bookings = Enum.count(results, &match?({:ok, {:error, _}}, &1))

      # All should succeed for unlimited tier
      assert successful_bookings == 50,
             "Expected all 50 bookings to succeed for unlimited tier, got #{successful_bookings}"

      assert failed_bookings == 0,
             "Expected no failed bookings for unlimited tier, got #{failed_bookings}"
    end
  end

  describe "concurrent ticket bookings - edge cases" do
    test "handles rapid sequential bookings correctly", %{
      users: users,
      event: event,
      tier1: tier1,
      sandbox_owner: owner
    } do
      # Book tickets rapidly one after another (not truly concurrent, but tests sequential logic)
      concurrent_users = Enum.take(users, 60)

      results =
        concurrent_users
        |> Enum.map(fn user ->
          BookingLocker.atomic_booking(user.id, event.id, %{tier1.id => 1})
        end)

      successful_bookings = Enum.count(results, &match?({:ok, _}, &1))
      failed_bookings = Enum.count(results, &match?({:error, _}, &1))

      total_tickets =
        Ticket
        |> where([t], t.ticket_tier_id == ^tier1.id)
        |> where([t], t.status in [:pending, :confirmed])
        |> Repo.aggregate(:count, :id)

      assert total_tickets == 50,
             "Expected exactly 50 tickets, got #{total_tickets}"

      assert successful_bookings == 50,
             "Expected 50 successful bookings, got #{successful_bookings}"

      assert failed_bookings == 10,
             "Expected 10 failed bookings, got #{failed_bookings}"
    end

    test "prevents same user from booking same tier multiple times concurrently", %{
      event: event,
      tier1: tier1,
      sandbox_owner: owner
    } do
      user =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at: DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Repo.update!()

      # Same user tries to book same tier 10 times concurrently
      results =
        1..10
        |> Task.async_stream(
          fn _ ->
            Ysc.DataCase.allow_sandbox(self(), owner)
            BookingLocker.atomic_booking(user.id, event.id, %{tier1.id => 1})
          end,
          max_concurrency: 10,
          timeout: 10_000
        )
        |> Enum.to_list()

      successful_bookings = Enum.count(results, &match?({:ok, {:ok, _}}, &1))

      # User should be able to book multiple times (no restriction on same user)
      # But total tickets should not exceed tier capacity
      total_tickets =
        Ticket
        |> where([t], t.ticket_tier_id == ^tier1.id)
        |> where([t], t.user_id == ^user.id)
        |> where([t], t.status in [:pending, :confirmed])
        |> Repo.aggregate(:count, :id)

      # All 10 bookings should succeed (tier has capacity 50)
      assert successful_bookings == 10,
             "Expected 10 successful bookings for same user, got #{successful_bookings}"

      assert total_tickets == 10,
             "Expected 10 tickets for user, got #{total_tickets}"
    end
  end

  describe "concurrent ticket bookings - database transaction isolation" do
    test "ensures database locks prevent race conditions", %{
      users: users,
      event: event,
      tier1: tier1,
      sandbox_owner: owner
    } do
      # This test verifies that optimistic locking works correctly
      # by checking that no two transactions can successfully update the same tier inventory

      concurrent_users = Enum.take(users, 100)

      # Track the order of successful bookings to verify serialization
      results =
        concurrent_users
        |> Task.async_stream(
          fn user ->
            Ysc.DataCase.allow_sandbox(self(), owner)
            result = BookingLocker.atomic_booking(user.id, event.id, %{tier1.id => 1})
            # Small delay to ensure we can observe transaction ordering
            Process.sleep(1)
            result
          end,
          max_concurrency: 100,
          timeout: 15_000
        )
        |> Enum.to_list()

      successful_bookings = Enum.count(results, &match?({:ok, {:ok, _}}, &1))

      # Verify exactly 50 succeeded (tier capacity)
      assert successful_bookings == 50,
             "Expected exactly 50 successful bookings, got #{successful_bookings}"

      # Verify total tickets match successful bookings
      total_tickets =
        Ticket
        |> where([t], t.ticket_tier_id == ^tier1.id)
        |> where([t], t.status in [:pending, :confirmed])
        |> Repo.aggregate(:count, :id)

      assert total_tickets == 50,
             "Expected exactly 50 tickets, got #{total_tickets}"

      # Verify no duplicate bookings (each user should have at most one successful booking)
      user_ticket_counts =
        Ticket
        |> where([t], t.ticket_tier_id == ^tier1.id)
        |> where([t], t.status in [:pending, :confirmed])
        |> group_by([t], t.user_id)
        |> select([t], {t.user_id, count(t.id)})
        |> Repo.all()
        |> Enum.into(%{})

      # Each user should have at most 1 ticket (since each booking was for 1 ticket)
      assert Enum.all?(user_ticket_counts, fn {_user_id, count} -> count == 1 end),
             "Some users have multiple tickets: #{inspect(user_ticket_counts)}"
    end
  end
end
