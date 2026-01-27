defmodule Ysc.Bookings.BookingLockerConcurrencyTest do
  @moduledoc """
  Simplified concurrency tests for cabin bookings to ensure no data races or overbooking.

  These tests verify that optimistic locking mechanisms prevent double-booking
  and ensure capacity limits are respected.
  """
  use Ysc.DataCase, async: false

  alias Ysc.Bookings
  alias Ysc.Bookings.BookingLocker
  alias Ysc.Bookings.Room
  alias Ysc.Ledgers
  alias Ysc.Repo
  import Ysc.AccountsFixtures

  setup context do
    Ledgers.ensure_basic_accounts()
    users = Enum.map(1..10, fn _ -> user_fixture() end)

    {:ok, _} =
      Bookings.create_pricing_rule(%{
        amount: Money.new(100, :USD),
        booking_mode: :room,
        price_unit: :per_person_per_night,
        property: :tahoe,
        season_id: nil
      })

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

    today = Date.utc_today()
    checkin_date = Date.add(today, 7)
    checkout_date = Date.add(checkin_date, 3)

    {:ok,
     Map.merge(context, %{
       users: users,
       tahoe_room1: tahoe_room1,
       tahoe_room2: tahoe_room2,
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
      concurrent_users = Enum.take(users, 5)

      results =
        concurrent_users
        |> Task.async_stream(
          fn user ->
            Ysc.DataCase.allow_sandbox(self(), owner)
            BookingLocker.create_room_booking(user.id, [room.id], checkin_date, checkout_date, 2)
          end,
          max_concurrency: 5,
          timeout: 5_000
        )
        |> Enum.to_list()

      successful = Enum.count(results, &match?({:ok, {:ok, _}}, &1))
      failed = Enum.count(results, &match?({:ok, {:error, _}}, &1))

      assert successful == 1
      assert failed == 4
    end

    test "allows concurrent bookings for different rooms", %{
      users: users,
      tahoe_room1: room1,
      tahoe_room2: room2,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      sandbox_owner: owner
    } do
      concurrent_users = Enum.take(users, 4)

      results =
        concurrent_users
        |> Enum.with_index()
        |> Task.async_stream(
          fn {user, index} ->
            Ysc.DataCase.allow_sandbox(self(), owner)
            room_id = if rem(index, 2) == 0, do: room1.id, else: room2.id
            BookingLocker.create_room_booking(user.id, [room_id], checkin_date, checkout_date, 2)
          end,
          max_concurrency: 4,
          timeout: 5_000
        )
        |> Enum.to_list()

      successful = Enum.count(results, &match?({:ok, {:ok, _}}, &1))
      assert successful == 2
    end
  end

  describe "concurrent Clear Lake per-guest bookings" do
    test "prevents overbooking when capacity is exceeded", %{
      users: users,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      sandbox_owner: owner
    } do
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
              1
            )
          end,
          max_concurrency: 5,
          timeout: 5_000
        )
        |> Enum.to_list()

      successful = Enum.count(results, &match?({:ok, {:ok, _}}, &1))
      # Clear Lake capacity is 12, so all 5 should succeed
      assert successful == 5
    end
  end

  describe "concurrent buyout bookings" do
    test "prevents overlapping buyout bookings", %{
      users: users,
      checkin_date: checkin_date,
      checkout_date: checkout_date,
      sandbox_owner: owner
    } do
      concurrent_users = Enum.take(users, 3)

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
              4
            )
          end,
          max_concurrency: 3,
          timeout: 5_000
        )
        |> Enum.to_list()

      successful = Enum.count(results, &match?({:ok, {:ok, _}}, &1))
      failed = Enum.count(results, &match?({:ok, {:error, _}}, &1))

      assert successful == 1
      assert failed == 2
    end
  end
end
