defmodule Ysc.Bookings.BookingLockerConcurrencyTest do
  @moduledoc """
  Extensive concurrency tests for cabin bookings to ensure no data races or overbooking.

  These tests simulate high-concurrency scenarios where multiple users attempt to book
  cabins simultaneously, verifying that optimistic locking mechanisms prevent
  double-booking and ensure capacity limits are respected for:
  - Tahoe room bookings
  - Clear Lake per-guest bookings
  - Buyout bookings

  Note: These tests use async: false because concurrent tasks within a test need
  to share the same database connection pool to properly test optimistic locking.
  """
  use Ysc.DataCase, async: false

  alias Ysc.Bookings.BookingLocker
  alias Ysc.Bookings.{Booking, PropertyInventory, RoomInventory, Room}
  alias Ysc.Repo
  import Ysc.AccountsFixtures

  setup context do
    users = Enum.map(1..50, fn _ -> user_fixture() end)

    # Create Tahoe rooms directly
    tahoe_room1 =
      %Room{
        name: "Tahoe Room 1",
        property: :tahoe,
        capacity_max: 4,
        is_active: true
      }
      |> Repo.insert!()

    tahoe_room2 =
      %Room{
        name: "Tahoe Room 2",
        property: :tahoe,
        capacity_max: 4,
        is_active: true
      }
      |> Repo.insert!()

    tahoe_room3 =
      %Room{
        name: "Tahoe Room 3",
        property: :tahoe,
        capacity_max: 2,
        is_active: true
      }
      |> Repo.insert!()

    # Create Clear Lake rooms (for reference, though Clear Lake uses per-guest booking)
    clear_lake_room1 =
      %Room{
        name: "Clear Lake Room 1",
        property: :clear_lake,
        capacity_max: 6,
        is_active: true
      }
      |> Repo.insert!()

    # Set up dates
    today = Date.utc_today()
    checkin_date = Date.add(today, 7)
    # 3 nights
    checkout_date = Date.add(checkin_date, 3)

    {:ok,
     Map.merge(context, %{
       users: users,
       tahoe_room1: tahoe_room1,
       tahoe_room2: tahoe_room2,
       tahoe_room3: tahoe_room3,
       clear_lake_room1: clear_lake_room1,
       checkin_date: checkin_date,
       checkout_date: checkout_date
     })}
  end

  describe "concurrent Tahoe room bookings" do
    test "prevents double-booking same room for same dates", %{
      users: users,
      tahoe_room1: room,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      sandbox_owner: owner
    } do
      # 20 users try to book the same room for the same dates simultaneously
      # Each concurrent task needs its own database connection for proper locking
      concurrent_users = Enum.take(users, 20)

      results =
        concurrent_users
        |> Task.async_stream(
          fn user ->
            # Allow this task process to checkout its own database connection
            # This is critical for proper optimistic locking behavior with concurrent transactions
            Ysc.DataCase.allow_sandbox(self(), owner)

            BookingLocker.create_room_booking(
              user.id,
              [room.id],
              checkin_date,
              checkout_date,
              2
            )
          end,
          max_concurrency: 20,
          timeout: 15_000
        )
        |> Enum.to_list()

      successful_bookings =
        Enum.count(results, fn
          {:ok, {:ok, _}} -> true
          _ -> false
        end)

      failed_bookings = Enum.count(results, &match?({:ok, {:error, _}}, &1))

      # Only one booking should succeed (same room, same dates)
      assert successful_bookings == 1,
             "Expected exactly 1 successful booking, got #{successful_bookings}. Failed: #{failed_bookings}"

      assert failed_bookings == 19,
             "Expected 19 failed bookings, got #{failed_bookings}"

      # Verify room inventory is properly locked
      days = Date.range(checkin_date, Date.add(checkout_date, -1)) |> Enum.to_list()

      for day <- days do
        room_inv =
          Repo.get_by(RoomInventory, room_id: room.id, day: day)

        assert room_inv != nil, "Room inventory should exist for day #{day}"

        assert room_inv.held == true or room_inv.booked == true,
               "Room should be held or booked for day #{day}"
      end
    end

    test "allows concurrent bookings for different rooms", %{
      users: users,
      tahoe_room1: room1,
      tahoe_room2: room2,
      tahoe_room3: room3,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      sandbox_owner: owner
    } do
      # 30 users try to book different rooms simultaneously for the same dates
      # Since each room can only be booked once for a given date range,
      # only 1 booking per room should succeed (3 total)
      concurrent_users = Enum.take(users, 30)

      results =
        concurrent_users
        |> Enum.with_index()
        |> Task.async_stream(
          fn {user, index} ->
            Ysc.DataCase.allow_sandbox(self(), owner)
            # Distribute across 3 rooms
            room_id =
              case rem(index, 3) do
                0 -> room1.id
                1 -> room2.id
                2 -> room3.id
              end

            BookingLocker.create_room_booking(
              user.id,
              [room_id],
              checkin_date,
              checkout_date,
              2
            )
          end,
          max_concurrency: 30,
          timeout: 15_000
        )
        |> Enum.to_list()

      successful_bookings = Enum.count(results, &match?({:ok, {:ok, _}}, &1))
      failed_bookings = Enum.count(results, &match?({:ok, {:error, _}}, &1))

      # Only 3 bookings should succeed (1 per room for the same dates)
      assert successful_bookings == 3,
             "Expected 3 successful bookings (1 per room), got #{successful_bookings}"

      assert failed_bookings == 27,
             "Expected 27 failed bookings, got #{failed_bookings}"

      # Verify each room has exactly 1 booking
      for room <- [room1, room2, room3] do
        room_bookings =
          Booking
          |> where([b], b.property == :tahoe)
          |> join(:inner, [b], br in assoc(b, :rooms))
          |> where([b, br], br.id == ^room.id)
          |> where([b], b.checkin_date == ^checkin_date)
          |> where([b], b.checkout_date == ^checkout_date)
          |> where([b], b.status in [:hold, :complete])
          |> Repo.aggregate(:count, :id)

        assert room_bookings == 1,
               "Expected 1 booking for room #{room.id}, got #{room_bookings}"
      end
    end

    test "prevents overlapping date bookings for same room", %{
      users: users,
      tahoe_room1: room,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      sandbox_owner: owner
    } do
      # First user books checkin_date to checkout_date
      [user1 | rest_users] = users

      {:ok, _booking1} =
        BookingLocker.create_room_booking(
          user1.id,
          [room.id],
          checkin_date,
          checkout_date,
          2
        )

      # Other users try to book overlapping dates concurrently
      overlapping_dates = [
        # Exact same dates
        {checkin_date, checkout_date},
        # Overlaps start
        {Date.add(checkin_date, -1), checkout_date},
        # Overlaps end
        {checkin_date, Date.add(checkout_date, 1)},
        # Overlaps middle
        {Date.add(checkin_date, 1), Date.add(checkout_date, 1)}
      ]

      concurrent_users = Enum.take(rest_users, length(overlapping_dates))

      results =
        concurrent_users
        |> Enum.zip(overlapping_dates)
        |> Task.async_stream(
          fn {user, {ci_date, co_date}} ->
            Ysc.DataCase.allow_sandbox(self(), owner)
            BookingLocker.create_room_booking(user.id, [room.id], ci_date, co_date, 2)
          end,
          max_concurrency: length(overlapping_dates),
          timeout: 15_000
        )
        |> Enum.to_list()

      successful_bookings =
        Enum.count(results, fn
          {:ok, {:ok, _}} -> true
          _ -> false
        end)

      failed_bookings = Enum.count(results, &match?({:ok, {:error, _}}, &1))

      # All overlapping bookings should fail
      assert successful_bookings == 0,
             "Expected no successful overlapping bookings, got #{successful_bookings}"

      assert failed_bookings == length(overlapping_dates),
             "Expected all overlapping bookings to fail, got #{failed_bookings}"
    end

    test "allows non-overlapping bookings for same room", %{
      users: users,
      tahoe_room1: room,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      sandbox_owner: owner
    } do
      # First user books original dates
      [user1 | rest_users] = users

      {:ok, _booking1} =
        BookingLocker.create_room_booking(
          user1.id,
          [room.id],
          checkin_date,
          checkout_date,
          2
        )

      # Other users book non-overlapping dates (after checkout)
      # Since they're all booking the SAME non-overlapping dates concurrently,
      # only 1 should succeed
      non_overlapping_checkin = checkout_date
      non_overlapping_checkout = Date.add(non_overlapping_checkin, 2)

      concurrent_users = Enum.take(rest_users, 5)

      results =
        concurrent_users
        |> Task.async_stream(
          fn user ->
            Ysc.DataCase.allow_sandbox(self(), owner)

            BookingLocker.create_room_booking(
              user.id,
              [room.id],
              non_overlapping_checkin,
              non_overlapping_checkout,
              2
            )
          end,
          max_concurrency: 5,
          timeout: 15_000
        )
        |> Enum.to_list()

      successful_bookings = Enum.count(results, &match?({:ok, {:ok, _}}, &1))
      failed_bookings = Enum.count(results, &match?({:ok, {:error, _}}, &1))

      # Only 1 non-overlapping booking should succeed (same dates, same room)
      assert successful_bookings == 1,
             "Expected 1 successful booking, got #{successful_bookings}"

      assert failed_bookings == 4,
             "Expected 4 failed bookings, got #{failed_bookings}"

      # Verify total bookings for the room
      total_bookings =
        Booking
        |> where([b], b.property == :tahoe)
        |> join(:inner, [b], br in assoc(b, :rooms))
        |> where([b, br], br.id == ^room.id)
        |> where([b], b.status in [:hold, :complete])
        |> Repo.aggregate(:count, :id)

      assert total_bookings == 2,
             "Expected 2 total bookings (1 original + 1 non-overlapping), got #{total_bookings}"
    end
  end

  describe "concurrent Clear Lake per-guest bookings" do
    test "prevents overbooking when capacity is exceeded", %{
      users: users,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      sandbox_owner: owner
    } do
      # Clear Lake has capacity of 12 guests per day
      # 20 users try to book 1 guest each simultaneously (total 20 guests > 12 capacity)
      concurrent_users = Enum.take(users, 20)

      results =
        concurrent_users
        |> Task.async_stream(
          fn user ->
            Ysc.DataCase.allow_sandbox(self(), owner)

            BookingLocker.create_per_guest_booking(
              user.id,
              :clear_lake,
              checkin_date,
              checkout_date,
              1
            )
          end,
          max_concurrency: 20,
          timeout: 15_000
        )
        |> Enum.to_list()

      successful_bookings =
        Enum.count(results, fn
          {:ok, {:ok, _}} -> true
          _ -> false
        end)

      failed_bookings = Enum.count(results, &match?({:ok, {:error, _}}, &1))

      # Exactly 12 bookings should succeed (capacity limit)
      assert successful_bookings == 12,
             "Expected exactly 12 successful bookings, got #{successful_bookings}. Failed: #{failed_bookings}"

      assert failed_bookings == 8,
             "Expected 8 failed bookings, got #{failed_bookings}"

      # Verify capacity_held matches successful bookings
      days = Date.range(checkin_date, Date.add(checkout_date, -1)) |> Enum.to_list()

      for day <- days do
        prop_inv = Repo.get_by(PropertyInventory, property: :clear_lake, day: day)

        assert prop_inv != nil, "Property inventory should exist for day #{day}"

        assert prop_inv.capacity_held == 12,
               "Expected capacity_held=12 for day #{day}, got #{prop_inv.capacity_held}"
      end
    end

    test "handles mixed guest counts correctly", %{
      users: users,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      sandbox_owner: owner
    } do
      # Clear Lake capacity: 12 guests
      # Create bookings with varying guest counts
      concurrent_users = Enum.take(users, 10)

      # Total: 15 guests
      guest_counts = [2, 2, 2, 2, 2, 1, 1, 1, 1, 1]

      results =
        concurrent_users
        |> Enum.zip(guest_counts)
        |> Task.async_stream(
          fn {user, guests} ->
            Ysc.DataCase.allow_sandbox(self(), owner)

            BookingLocker.create_per_guest_booking(
              user.id,
              :clear_lake,
              checkin_date,
              checkout_date,
              guests
            )
          end,
          max_concurrency: 10,
          timeout: 15_000
        )
        |> Enum.to_list()

      successful_bookings =
        Enum.count(results, fn
          {:ok, {:ok, _}} -> true
          _ -> false
        end)

      failed_bookings = Enum.count(results, &match?({:ok, {:error, _}}, &1))

      # Calculate total guests from successful bookings
      days = Date.range(checkin_date, Date.add(checkout_date, -1)) |> Enum.to_list()

      for day <- days do
        prop_inv = Repo.get_by(PropertyInventory, property: :clear_lake, day: day)

        assert prop_inv != nil

        assert prop_inv.capacity_held <= 12,
               "Capacity exceeded: #{prop_inv.capacity_held} > 12 for day #{day}"
      end

      # Verify we got some successful and some failed bookings
      assert successful_bookings > 0, "Expected at least some successful bookings"
      assert failed_bookings > 0, "Expected at least some failed bookings"
    end

    test "prevents overbooking when multiple users book multiple guests", %{
      users: users,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      sandbox_owner: owner
    } do
      # Clear Lake capacity: 12 guests
      # 5 users try to book 3 guests each (total 15 guests > 12 capacity)
      concurrent_users = Enum.take(users, 5)

      results =
        concurrent_users
        |> Task.async_stream(
          fn user ->
            Ysc.DataCase.allow_sandbox(self(), owner)

            BookingLocker.create_per_guest_booking(
              user.id,
              :clear_lake,
              checkin_date,
              checkout_date,
              3
            )
          end,
          max_concurrency: 5,
          timeout: 15_000
        )
        |> Enum.to_list()

      successful_bookings =
        Enum.count(results, fn
          {:ok, {:ok, _}} -> true
          _ -> false
        end)

      failed_bookings = Enum.count(results, &match?({:ok, {:error, _}}, &1))

      # Should allow 4 bookings (4 * 3 = 12 guests) and fail 1 booking
      assert successful_bookings == 4,
             "Expected 4 successful bookings (12 guests total), got #{successful_bookings}"

      assert failed_bookings == 1,
             "Expected 1 failed booking, got #{failed_bookings}"

      # Verify capacity
      days = Date.range(checkin_date, Date.add(checkout_date, -1)) |> Enum.to_list()

      for day <- days do
        prop_inv = Repo.get_by(PropertyInventory, property: :clear_lake, day: day)

        assert prop_inv.capacity_held == 12,
               "Expected capacity_held=12, got #{prop_inv.capacity_held}"
      end
    end
  end

  describe "concurrent buyout bookings" do
    test "prevents multiple buyout bookings for same dates", %{
      users: users,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      sandbox_owner: owner
    } do
      # 10 users try to book buyout for same dates simultaneously
      concurrent_users = Enum.take(users, 10)

      results =
        concurrent_users
        |> Task.async_stream(
          fn user ->
            Ysc.DataCase.allow_sandbox(self(), owner)

            BookingLocker.create_buyout_booking(
              user.id,
              :clear_lake,
              checkin_date,
              checkout_date,
              15
            )
          end,
          max_concurrency: 10,
          timeout: 15_000
        )
        |> Enum.to_list()

      successful_bookings =
        Enum.count(results, fn
          {:ok, {:ok, _}} -> true
          _ -> false
        end)

      failed_bookings = Enum.count(results, &match?({:ok, {:error, _}}, &1))

      # Only one buyout booking should succeed
      assert successful_bookings == 1,
             "Expected exactly 1 successful buyout booking, got #{successful_bookings}. Failed: #{failed_bookings}"

      assert failed_bookings == 9,
             "Expected 9 failed buyout bookings, got #{failed_bookings}"

      # Verify buyout_held is set
      days = Date.range(checkin_date, Date.add(checkout_date, -1)) |> Enum.to_list()

      for day <- days do
        prop_inv = Repo.get_by(PropertyInventory, property: :clear_lake, day: day)

        assert prop_inv != nil

        assert prop_inv.buyout_held == true,
               "Buyout should be held for day #{day}"
      end
    end

    test "prevents buyout when rooms are already booked (Tahoe)", %{
      users: users,
      tahoe_room1: room,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      sandbox_owner: owner
    } do
      # First user books a room
      [user1 | rest_users] = users

      {:ok, _room_booking} =
        BookingLocker.create_room_booking(
          user1.id,
          [room.id],
          checkin_date,
          checkout_date,
          2
        )

      # Other users try to book buyout for same dates
      concurrent_users = Enum.take(rest_users, 5)

      results =
        concurrent_users
        |> Task.async_stream(
          fn user ->
            Ysc.DataCase.allow_sandbox(self(), owner)

            BookingLocker.create_buyout_booking(
              user.id,
              :tahoe,
              checkin_date,
              checkout_date,
              12
            )
          end,
          max_concurrency: 5,
          timeout: 15_000
        )
        |> Enum.to_list()

      successful_bookings =
        Enum.count(results, fn
          {:ok, {:ok, _}} -> true
          _ -> false
        end)

      failed_bookings = Enum.count(results, &match?({:ok, {:error, _}}, &1))

      # All buyout attempts should fail (room already booked)
      assert successful_bookings == 0,
             "Expected no successful buyout bookings (room already booked), got #{successful_bookings}"

      assert failed_bookings == 5,
             "Expected all buyout attempts to fail, got #{failed_bookings}"
    end

    test "prevents room bookings when buyout is active", %{
      users: users,
      tahoe_room1: room,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      sandbox_owner: owner
    } do
      # First user books buyout
      [user1 | rest_users] = users

      {:ok, _buyout_booking} =
        BookingLocker.create_buyout_booking(
          user1.id,
          :tahoe,
          checkin_date,
          checkout_date,
          12
        )

      # Other users try to book rooms for same dates
      concurrent_users = Enum.take(rest_users, 5)

      results =
        concurrent_users
        |> Task.async_stream(
          fn user ->
            BookingLocker.create_room_booking(
              user.id,
              [room.id],
              checkin_date,
              checkout_date,
              2
            )
          end,
          max_concurrency: 5,
          timeout: 15_000
        )
        |> Enum.to_list()

      successful_bookings =
        Enum.count(results, fn
          {:ok, {:ok, _}} -> true
          _ -> false
        end)

      failed_bookings = Enum.count(results, &match?({:ok, {:error, _}}, &1))

      # All room booking attempts should fail (buyout active)
      assert successful_bookings == 0,
             "Expected no successful room bookings (buyout active), got #{successful_bookings}"

      assert failed_bookings == 5,
             "Expected all room booking attempts to fail, got #{failed_bookings}"
    end

    test "prevents per-guest bookings when buyout is active (Clear Lake)", %{
      users: users,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      sandbox_owner: owner
    } do
      # First user books buyout
      [user1 | rest_users] = users

      {:ok, _buyout_booking} =
        BookingLocker.create_buyout_booking(
          user1.id,
          :clear_lake,
          checkin_date,
          checkout_date,
          15
        )

      # Other users try to book per-guest for same dates
      concurrent_users = Enum.take(rest_users, 5)

      results =
        concurrent_users
        |> Task.async_stream(
          fn user ->
            BookingLocker.create_per_guest_booking(
              user.id,
              :clear_lake,
              checkin_date,
              checkout_date,
              2
            )
          end,
          max_concurrency: 5,
          timeout: 15_000
        )
        |> Enum.to_list()

      successful_bookings =
        Enum.count(results, fn
          {:ok, {:ok, _}} -> true
          _ -> false
        end)

      failed_bookings = Enum.count(results, &match?({:ok, {:error, _}}, &1))

      # All per-guest booking attempts should fail (buyout active)
      assert successful_bookings == 0,
             "Expected no successful per-guest bookings (buyout active), got #{successful_bookings}"

      assert failed_bookings == 5,
             "Expected all per-guest booking attempts to fail, got #{failed_bookings}"
    end
  end

  describe "concurrent bookings - database transaction isolation" do
    test "ensures optimistic locking prevents race conditions in room bookings", %{
      users: users,
      tahoe_room1: room,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      sandbox_owner: owner
    } do
      # This test verifies that optimistic locking works correctly
      # by checking that no two transactions can successfully update the same inventory

      concurrent_users = Enum.take(users, 30)

      results =
        concurrent_users
        |> Task.async_stream(
          fn user ->
            Ysc.DataCase.allow_sandbox(self(), owner)

            result =
              BookingLocker.create_room_booking(
                user.id,
                [room.id],
                checkin_date,
                checkout_date,
                2
              )

            # Small delay to ensure we can observe transaction ordering
            Process.sleep(1)
            result
          end,
          max_concurrency: 30,
          timeout: 15_000
        )
        |> Enum.to_list()

      successful_bookings = Enum.count(results, &match?({:ok, {:ok, _}}, &1))

      # Only one booking should succeed (same room, same dates)
      assert successful_bookings == 1,
             "Expected exactly 1 successful booking, got #{successful_bookings}"

      # Verify room inventory is properly set
      days = Date.range(checkin_date, Date.add(checkout_date, -1)) |> Enum.to_list()

      for day <- days do
        room_inv = Repo.get_by(RoomInventory, room_id: room.id, day: day)

        assert room_inv != nil
        assert room_inv.held == true or room_inv.booked == true
      end
    end

    test "ensures optimistic locking prevents race conditions in per-guest bookings", %{
      users: users,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      sandbox_owner: owner
    } do
      # Clear Lake capacity: 12 guests
      # 20 users try to book 1 guest each
      concurrent_users = Enum.take(users, 20)

      results =
        concurrent_users
        |> Task.async_stream(
          fn user ->
            Ysc.DataCase.allow_sandbox(self(), owner)

            result =
              BookingLocker.create_per_guest_booking(
                user.id,
                :clear_lake,
                checkin_date,
                checkout_date,
                1
              )

            Process.sleep(1)
            result
          end,
          max_concurrency: 20,
          timeout: 15_000
        )
        |> Enum.to_list()

      successful_bookings = Enum.count(results, &match?({:ok, {:ok, _}}, &1))

      # Exactly 12 bookings should succeed (capacity limit)
      assert successful_bookings == 12,
             "Expected exactly 12 successful bookings, got #{successful_bookings}"

      # Verify capacity_held matches successful bookings
      days = Date.range(checkin_date, Date.add(checkout_date, -1)) |> Enum.to_list()

      for day <- days do
        prop_inv = Repo.get_by(PropertyInventory, property: :clear_lake, day: day)

        assert prop_inv != nil

        assert prop_inv.capacity_held == 12,
               "Expected capacity_held=12, got #{prop_inv.capacity_held}"
      end
    end
  end

  describe "concurrent bookings - hold expiration and release" do
    test "allows new bookings after hold is released", %{
      users: users,
      tahoe_room1: room,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      sandbox_owner: owner
    } do
      # First user creates a hold booking
      [user1 | rest_users] = users

      {:ok, booking1} =
        BookingLocker.create_room_booking(
          user1.id,
          [room.id],
          checkin_date,
          checkout_date,
          2
        )

      # Verify room is held
      days = Date.range(checkin_date, Date.add(checkout_date, -1)) |> Enum.to_list()

      for day <- days do
        room_inv = Repo.get_by(RoomInventory, room_id: room.id, day: day)
        assert room_inv.held == true
      end

      # Release the hold
      {:ok, _released_booking} = BookingLocker.release_hold(booking1.id)

      # Verify room is no longer held
      for day <- days do
        room_inv = Repo.get_by(RoomInventory, room_id: room.id, day: day)
        assert room_inv.held == false
      end

      # Now another user should be able to book
      [user2 | _] = rest_users

      {:ok, _booking2} =
        BookingLocker.create_room_booking(
          user2.id,
          [room.id],
          checkin_date,
          checkout_date,
          2
        )

      # Verify room is held again
      for day <- days do
        room_inv = Repo.get_by(RoomInventory, room_id: room.id, day: day)
        assert room_inv.held == true
      end
    end

    test "prevents new bookings while hold is active", %{
      users: users,
      tahoe_room1: room,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      sandbox_owner: owner
    } do
      # First user creates a hold booking
      [user1 | rest_users] = users

      {:ok, _booking1} =
        BookingLocker.create_room_booking(
          user1.id,
          [room.id],
          checkin_date,
          checkout_date,
          2
        )

      # Other users try to book while hold is active
      concurrent_users = Enum.take(rest_users, 5)

      results =
        concurrent_users
        |> Task.async_stream(
          fn user ->
            BookingLocker.create_room_booking(
              user.id,
              [room.id],
              checkin_date,
              checkout_date,
              2
            )
          end,
          max_concurrency: 5,
          timeout: 15_000
        )
        |> Enum.to_list()

      successful_bookings =
        Enum.count(results, fn
          {:ok, {:ok, _}} -> true
          _ -> false
        end)

      failed_bookings = Enum.count(results, &match?({:ok, {:error, _}}, &1))

      # All should fail while hold is active
      assert successful_bookings == 0,
             "Expected no successful bookings while hold is active, got #{successful_bookings}"

      assert failed_bookings == 5,
             "Expected all booking attempts to fail, got #{failed_bookings}"
    end
  end
end
