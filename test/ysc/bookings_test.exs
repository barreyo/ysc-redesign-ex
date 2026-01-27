defmodule Ysc.BookingsTest do
  @moduledoc """
  Tests for Ysc.Bookings context module.
  """
  use Ysc.DataCase, async: true

  alias Ysc.Bookings
  alias Ysc.Bookings.{Booking, Season, Room, RoomCategory}
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    :ok
  end

  describe "seasons" do
    test "list_seasons/0 returns all seasons" do
      season1 = create_season_fixture(%{name: "Summer", property: :tahoe})
      season2 = create_season_fixture(%{name: "Winter", property: :clear_lake})

      seasons = Bookings.list_seasons()
      assert length(seasons) >= 2
      assert Enum.any?(seasons, &(&1.id == season1.id))
      assert Enum.any?(seasons, &(&1.id == season2.id))
    end

    test "list_seasons/1 filters by property" do
      season1 = create_season_fixture(%{name: "Summer", property: :tahoe})
      _season2 = create_season_fixture(%{name: "Winter", property: :clear_lake})

      seasons = Bookings.list_seasons(:tahoe)
      assert Enum.any?(seasons, &(&1.id == season1.id))
      refute Enum.any?(seasons, &(&1.property == :clear_lake))
    end

    test "get_season!/1 returns the season with given id" do
      season = create_season_fixture()
      assert Bookings.get_season!(season.id).id == season.id
    end

    test "create_season/1 with valid data creates a season" do
      valid_attrs = %{
        name: "Summer",
        property: :tahoe,
        start_date: ~D[2025-06-01],
        end_date: ~D[2025-08-31]
      }

      assert {:ok, %Season{} = season} = Bookings.create_season(valid_attrs)
      assert season.name == "Summer"
      assert season.property == :tahoe
    end

    test "create_season/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Bookings.create_season(%{})
    end

    test "update_season/2 with valid data updates the season" do
      season = create_season_fixture()
      update_attrs = %{name: "Updated Summer"}

      assert {:ok, %Season{} = season} = Bookings.update_season(season, update_attrs)
      assert season.name == "Updated Summer"
    end

    test "update_season/2 with invalid data returns error changeset" do
      season = create_season_fixture()
      assert {:error, %Ecto.Changeset{}} = Bookings.update_season(season, %{name: nil})
      assert season == Bookings.get_season!(season.id)
    end

    test "delete_season/1 deletes the season" do
      season = create_season_fixture()
      assert {:ok, %Season{}} = Bookings.delete_season(season)
      assert_raise Ecto.NoResultsError, fn -> Bookings.get_season!(season.id) end
    end
  end

  describe "bookings" do
    test "list_bookings/0 returns all bookings" do
      booking1 = booking_fixture()
      booking2 = booking_fixture()

      bookings = Bookings.list_bookings()
      assert length(bookings) >= 2
      assert Enum.any?(bookings, &(&1.id == booking1.id))
      assert Enum.any?(bookings, &(&1.id == booking2.id))
    end

    test "list_bookings/1 filters by property" do
      booking1 = booking_fixture(%{property: :tahoe})
      _booking2 = booking_fixture(%{property: :clear_lake})

      bookings = Bookings.list_bookings(:tahoe)
      assert Enum.any?(bookings, &(&1.id == booking1.id))
      refute Enum.any?(bookings, &(&1.property == :clear_lake))
    end

    test "list_bookings/3 filters by date range" do
      checkin = Date.utc_today() |> Date.add(7)
      checkout = Date.add(checkin, 2)

      booking1 = booking_fixture(%{checkin_date: checkin, checkout_date: checkout})

      _booking2 =
        booking_fixture(%{
          checkin_date: Date.add(checkin, 30),
          checkout_date: Date.add(checkin, 32)
        })

      start_date = Date.add(checkin, -1)
      end_date = Date.add(checkout, 1)

      bookings = Bookings.list_bookings(nil, start_date, end_date)
      assert Enum.any?(bookings, &(&1.id == booking1.id))
    end

    test "get_booking!/1 returns the booking with given id" do
      booking = booking_fixture()
      found = Bookings.get_booking!(booking.id)
      assert found.id == booking.id
      assert Ecto.assoc_loaded?(found.user)
    end

    test "get_booking_by_reference_id/1 returns the booking" do
      booking = booking_fixture()
      found = Bookings.get_booking_by_reference_id(booking.reference_id)
      assert found.id == booking.id
    end

    test "create_booking/1 with valid data creates a booking" do
      user = user_fixture()
      checkin = Date.utc_today() |> Date.add(7)
      checkout = Date.add(checkin, 2)

      valid_attrs = %{
        user_id: user.id,
        checkin_date: checkin,
        checkout_date: checkout,
        guests_count: 2,
        property: :tahoe,
        booking_mode: :buyout,
        status: :draft,
        total_price: Money.new(200, :USD)
      }

      assert {:ok, %Booking{} = booking} = Bookings.create_booking(valid_attrs)
      assert booking.user_id == user.id
      assert booking.property == :tahoe
      assert booking.booking_mode == :buyout
    end

    test "create_booking/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Bookings.create_booking(%{})
    end

    test "update_booking/2 with valid data updates the booking" do
      booking = booking_fixture() |> Ysc.Repo.preload(:rooms)
      update_attrs = %{guests_count: 4}

      assert {:ok, %Booking{} = booking} = Bookings.update_booking(booking, update_attrs)
      assert booking.guests_count == 4
    end

    test "update_booking/2 with invalid data returns error changeset" do
      booking = booking_fixture() |> Ysc.Repo.preload(:rooms)
      assert {:error, %Ecto.Changeset{}} = Bookings.update_booking(booking, %{user_id: nil})
      # Compare by ID only since associations may differ
      reloaded = Bookings.get_booking!(booking.id)
      assert reloaded.id == booking.id
    end

    test "delete_booking/1 deletes the booking" do
      booking = booking_fixture()
      assert {:ok, %Booking{}} = Bookings.delete_booking(booking)
      assert_raise Ecto.NoResultsError, fn -> Bookings.get_booking!(booking.id) end
    end
  end

  describe "calculate_booking_price/4" do
    test "calculates price for buyout booking" do
      property = :tahoe
      checkin = Date.utc_today() |> Date.add(30)
      checkout = Date.add(checkin, 3)
      booking_mode = :buyout

      # Set up pricing rule for buyout
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(500, :USD),
          booking_mode: :buyout,
          price_unit: :buyout_fixed,
          property: :tahoe,
          season_id: nil
        })

      result = Bookings.calculate_booking_price(property, checkin, checkout, booking_mode)
      assert {:ok, total_price, breakdown} = result
      assert is_struct(total_price, Money)
      assert is_map(breakdown)
    end

    test "calculates price for room booking" do
      property = :tahoe
      checkin = Date.utc_today() |> Date.add(30)
      checkout = Date.add(checkin, 3)
      booking_mode = :room

      room = create_room_fixture(%{property: property})

      # Set up pricing rule for room booking - must match the room_id or room_category_id
      # Since the room has a category, we can match by room_id (most specific) or room_category_id
      {:ok, _} =
        Bookings.create_pricing_rule(%{
          amount: Money.new(100, :USD),
          booking_mode: :room,
          price_unit: :per_person_per_night,
          property: :tahoe,
          room_id: room.id,
          season_id: nil
        })

      result =
        Bookings.calculate_booking_price(property, checkin, checkout, booking_mode,
          room_id: room.id,
          guests_count: 2
        )

      assert {:ok, total_price, breakdown} = result
      assert is_struct(total_price, Money)
      assert is_map(breakdown)
    end

    test "returns error for invalid booking dates" do
      property = :tahoe
      checkin = Date.utc_today() |> Date.add(30)
      # Invalid: checkout before checkin
      checkout = Date.add(checkin, -1)
      booking_mode = :buyout

      assert {:error, :invalid_date_range} =
               Bookings.calculate_booking_price(property, checkin, checkout, booking_mode)
    end
  end

  describe "rooms" do
    test "list_rooms/0 returns all rooms" do
      room1 = create_room_fixture(%{name: "Room 1", property: :tahoe})
      room2 = create_room_fixture(%{name: "Room 2", property: :clear_lake})

      rooms = Bookings.list_rooms()
      assert length(rooms) >= 2
      assert Enum.any?(rooms, &(&1.id == room1.id))
      assert Enum.any?(rooms, &(&1.id == room2.id))
    end

    test "list_rooms/1 filters by property" do
      room1 = create_room_fixture(%{property: :tahoe})
      _room2 = create_room_fixture(%{property: :clear_lake})

      rooms = Bookings.list_rooms(:tahoe)
      assert Enum.any?(rooms, &(&1.id == room1.id))
      refute Enum.any?(rooms, &(&1.property == :clear_lake))
    end

    test "get_room!/1 returns the room with given id" do
      room = create_room_fixture()
      assert Bookings.get_room!(room.id).id == room.id
    end

    test "create_room/1 with valid data creates a room" do
      category = create_room_category_fixture()

      valid_attrs = %{
        name: "Test Room",
        property: :tahoe,
        room_category_id: category.id,
        capacity_max: 4
      }

      assert {:ok, %Room{} = room} = Bookings.create_room(valid_attrs)
      assert room.name == "Test Room"
      assert room.property == :tahoe
    end

    test "update_room/2 with valid data updates the room" do
      room = create_room_fixture()
      update_attrs = %{name: "Updated Room"}

      assert {:ok, %Room{} = room} = Bookings.update_room(room, update_attrs)
      assert room.name == "Updated Room"
    end

    test "delete_room/1 deletes the room" do
      room = create_room_fixture()
      assert {:ok, %Room{}} = Bookings.delete_room(room)
      assert_raise Ecto.NoResultsError, fn -> Bookings.get_room!(room.id) end
    end
  end

  # Helper functions for creating test data
  defp create_season_fixture(attrs \\ %{}) do
    default_attrs = %{
      name: "Test Season #{System.unique_integer()}",
      property: :tahoe,
      start_date: ~D[2025-01-01],
      end_date: ~D[2025-12-31]
    }

    {:ok, season} =
      default_attrs
      |> Map.merge(attrs)
      |> Bookings.create_season()

    season
  end

  defp create_room_fixture(attrs \\ %{}) do
    category = create_room_category_fixture()

    default_attrs = %{
      name: "Test Room #{System.unique_integer()}",
      property: :tahoe,
      room_category_id: category.id,
      capacity_max: 4
    }

    {:ok, room} =
      default_attrs
      |> Map.merge(attrs)
      |> Bookings.create_room()

    room
  end

  defp create_room_category_fixture(attrs \\ %{}) do
    default_attrs = %{
      name: "Test Category #{System.unique_integer()}"
    }

    {:ok, category} =
      %RoomCategory{}
      |> RoomCategory.changeset(Map.merge(default_attrs, attrs))
      |> Ysc.Repo.insert()

    category
  end
end
