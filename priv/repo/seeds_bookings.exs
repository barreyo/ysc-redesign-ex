# Seeds for booking models
# Run with: mix run priv/repo/seeds_bookings.exs

alias Ysc.Repo
alias Ysc.Bookings.{RoomCategory, Season, Room, PricingRule, Booking, BookingValidator}
alias Ysc.Bookings.BookingProperty
alias Ysc.Accounts.User
alias Money

# Helper function to get or create records
defmodule BookingSeeds do
  def get_or_create(schema_module, attrs, unique_fields) when is_list(unique_fields) do
    query_params = Enum.map(unique_fields, fn field -> {field, Map.get(attrs, field)} end)

    case Repo.get_by(schema_module, query_params) do
      nil ->
        schema_module.changeset(schema_module.__struct__(), attrs)
        |> Repo.insert!()

      existing ->
        existing
    end
  end

  def get_or_create(schema_module, attrs, unique_field) when is_atom(unique_field) do
    get_or_create(schema_module, attrs, [unique_field])
  end
end

IO.puts("Creating booking seeds...")

# 1. Create room categories
IO.puts("Creating room categories...")

single_category =
  BookingSeeds.get_or_create(RoomCategory, %{name: "single", notes: "Single bed rooms (max 1 person)"}, :name)

standard_category =
  BookingSeeds.get_or_create(RoomCategory, %{name: "standard", notes: "Standard rooms"}, :name)

family_category =
  BookingSeeds.get_or_create(RoomCategory, %{name: "family", notes: "Family rooms (2 person minimum)"}, :name)

# 2. Create seasons for both properties
IO.puts("Creating seasons...")

# Seasons are recurring annually - we use a base year for the dates, but they repeat every year
# Winter: Nov 1 to April 30 (spans years - recurring pattern)
# Summer: May 1 to October 31 (same year - recurring pattern)
base_year = 2024

# Winter season: Nov 1 to April 30 (year-spanning, recurs annually)
winter_start = Date.new!(base_year, 11, 1)
winter_end = Date.new!(base_year + 1, 4, 30)
# Summer season: May 1 to October 31 (same year, recurs annually)
summer_start = Date.new!(base_year, 5, 1)
summer_end = Date.new!(base_year, 10, 31)

# Tahoe seasons (need to match on both name and property)
# Note: Seasons automatically recur every year based on month/day pattern
tahoe_winter =
  BookingSeeds.get_or_create(Season, %{
    name: "Winter",
    description: "Winter season for Tahoe cabin (Nov 1 - Apr 30, recurring annually)",
    property: :tahoe,
    start_date: winter_start,
    end_date: winter_end,
    is_default: false
  }, [:name, :property])

# Note: We'll set summer as default since it's longer, but you can adjust
tahoe_summer =
  BookingSeeds.get_or_create(Season, %{
    name: "Summer",
    description: "Summer season for Tahoe cabin (May 1 - Oct 31, recurring annually)",
    property: :tahoe,
    start_date: summer_start,
    end_date: summer_end,
    is_default: true
  }, [:name, :property])

# Clear Lake seasons
clear_lake_winter =
  BookingSeeds.get_or_create(Season, %{
    name: "Winter",
    description: "Winter season for Clear Lake cabin (Nov 1 - Apr 30, recurring annually)",
    property: :clear_lake,
    start_date: winter_start,
    end_date: winter_end,
    is_default: false
  }, [:name, :property])

clear_lake_summer =
  BookingSeeds.get_or_create(Season, %{
    name: "Summer",
    description: "Summer season for Clear Lake cabin (May 1 - Oct 31, recurring annually)",
    property: :clear_lake,
    start_date: summer_start,
    end_date: summer_end,
    is_default: true
  }, [:name, :property])

# 3. Create Tahoe rooms
IO.puts("Creating Tahoe rooms...")

room_names = ["Room 1", "Room 2", "Room 3", "Room 4", "Room 5a", "Room 5b", "Room 6", "Room 7"]

tahoe_rooms =
  Enum.map(room_names, fn name ->
    room_attrs =
      cond do
        name in ["Room 5a", "Room 5b"] ->
          # Single bed rooms
          %{
            name: name,
            description: "Single bed room (max 1 person)",
            property: :tahoe,
            capacity_max: 1,
            min_billable_occupancy: 1,
            is_single_bed: true,
            is_active: true,
            room_category_id: single_category.id,
            default_season_id: tahoe_summer.id
          }

        name == "Room 4" ->
          # Family room
          %{
            name: name,
            description: "Family room (2 person minimum)",
            property: :tahoe,
            capacity_max: 4,
            min_billable_occupancy: 2,
            is_single_bed: false,
            is_active: true,
            room_category_id: family_category.id,
            default_season_id: tahoe_summer.id
          }

        true ->
          # Standard rooms
          %{
            name: name,
            description: "Standard room",
            property: :tahoe,
            capacity_max: 4,
            min_billable_occupancy: 1,
            is_single_bed: false,
            is_active: true,
            room_category_id: standard_category.id,
            default_season_id: tahoe_summer.id
          }
      end

    # Match on both name and property to ensure uniqueness
    BookingSeeds.get_or_create(Room, room_attrs, [:name, :property])
  end)

# 4. Create pricing rules
IO.puts("Creating pricing rules...")

# Helper to get or create pricing rule
get_or_create_pricing_rule = fn attrs ->
  import Ecto.Query

  # Build query to find existing rule
  query = from pr in PricingRule, where: pr.booking_mode == ^attrs.booking_mode
  query = from pr in query, where: pr.price_unit == ^attrs.price_unit
  query = from pr in query, where: pr.property == ^attrs.property

  query =
    if Map.has_key?(attrs, :room_id) and not is_nil(attrs.room_id) do
      from pr in query, where: pr.room_id == ^attrs.room_id
    else
      from pr in query, where: is_nil(pr.room_id)
    end

  query =
    if Map.has_key?(attrs, :room_category_id) and not is_nil(attrs.room_category_id) do
      from pr in query, where: pr.room_category_id == ^attrs.room_category_id
    else
      from pr in query, where: is_nil(pr.room_category_id)
    end

  query =
    if Map.has_key?(attrs, :season_id) and not is_nil(attrs.season_id) do
      from pr in query, where: pr.season_id == ^attrs.season_id
    else
      from pr in query, where: is_nil(pr.season_id)
    end

  case Repo.one(query) do
    nil ->
      PricingRule.changeset(%PricingRule{}, attrs)
      |> Repo.insert!()

    existing ->
      existing
  end
end

# Clear Lake: Day bookings - $50 per person per night
get_or_create_pricing_rule.(%{
  amount: Money.new(50, :USD), # $50.00
  booking_mode: :day,
  price_unit: :per_guest_per_day,
  property: :clear_lake,
  season_id: nil # Applies to all seasons
})

# Clear Lake: Buyout - $500 per night
get_or_create_pricing_rule.(%{
  amount: Money.new(500, :USD), # $500.00
  booking_mode: :buyout,
  price_unit: :buyout_fixed,
  property: :clear_lake,
  season_id: nil # Applies to all seasons
})

# Tahoe: Summer buyout - $425 per night
get_or_create_pricing_rule.(%{
  amount: Money.new(425, :USD), # $425.00
  booking_mode: :buyout,
  price_unit: :buyout_fixed,
  property: :tahoe,
  season_id: tahoe_summer.id
})

# Tahoe: Base room pricing for standard rooms - $45 per person per night
# This applies to both summer and winter for standard category
get_or_create_pricing_rule.(%{
  amount: Money.new(45, :USD), # $45.00
  booking_mode: :room,
  price_unit: :per_person_per_night,
  property: :tahoe,
  room_category_id: standard_category.id,
  season_id: nil # Applies to all seasons
})

# Tahoe: Single bed room pricing - $35 per person per night (cheaper)
get_or_create_pricing_rule.(%{
  amount: Money.new(35, :USD), # $35.00
  booking_mode: :room,
  price_unit: :per_person_per_night,
  property: :tahoe,
  room_category_id: single_category.id,
  season_id: nil # Applies to all seasons
})

# Tahoe: Family room pricing - same as standard ($45 per person per night)
get_or_create_pricing_rule.(%{
  amount: Money.new(45, :USD), # $45.00
  booking_mode: :room,
  price_unit: :per_person_per_night,
  property: :tahoe,
  room_category_id: family_category.id,
  season_id: nil # Applies to all seasons
})

# 7. Create sample bookings
IO.puts("Creating sample bookings...")

import Ecto.Query

# Get some users for bookings
users = Repo.all(from u in User, where: u.state == :active, limit: 5)

if Enum.empty?(users) do
  IO.puts("Warning: No active users found. Please run seeds.exs first to create users.")
else
  # Get Tahoe rooms
  tahoe_rooms = Repo.all(from r in Room, where: r.property == :tahoe and r.is_active == true, limit: 5)

  if Enum.empty?(tahoe_rooms) do
    IO.puts("Warning: No Tahoe rooms found.")
  else
    today = Date.utc_today()
    # Create bookings for the current and next month
    base_date = Date.beginning_of_month(today)

    # Booking 1: One-night booking (minimum stay)
    if Enum.count(users) > 0 && Enum.count(tahoe_rooms) > 0 do
      checkin = Date.add(base_date, 5)
      checkout = Date.add(checkin, 1)  # At least 1 night (checkin < checkout)

      user = Enum.at(users, 0)
      room = Enum.at(tahoe_rooms, 0)

      Booking.changeset(%Booking{}, %{
        checkin_date: checkin,
        checkout_date: checkout,
        guests_count: min(2, room.capacity_max || 4),  # Respect room capacity
        property: :tahoe,
        booking_mode: :room,
        room_id: room.id,
        user_id: user.id
      })
      |> BookingValidator.validate(user: user)
      |> Repo.insert(on_conflict: :nothing)
    end

    # Booking 2: Multi-day booking (3 nights, max 4 for Tahoe)
    if Enum.count(users) > 1 && Enum.count(tahoe_rooms) > 1 do
      checkin = Date.add(base_date, 8)
      checkout = Date.add(checkin, 3)  # 3 nights

      user = Enum.at(users, 1)
      room = Enum.at(tahoe_rooms, 1)

      Booking.changeset(%Booking{}, %{
        checkin_date: checkin,
        checkout_date: checkout,
        guests_count: min(4, room.capacity_max || 4),  # Respect room capacity
        property: :tahoe,
        booking_mode: :room,
        room_id: room.id,
        user_id: user.id
      })
      |> BookingValidator.validate(user: user)
      |> Repo.insert(on_conflict: :nothing)
    end

    # Booking 3: Same-day turnaround (ends on date X, another starts on date X)
    if Enum.count(users) > 2 && Enum.count(tahoe_rooms) > 2 do
      room = Enum.at(tahoe_rooms, 2)

      # First booking ends on day 15
      checkin1 = Date.add(base_date, 13)
      checkout1 = Date.add(checkin1, 2)  # 2 nights (checkin < checkout)

      user1 = Enum.at(users, 2)
      Booking.changeset(%Booking{}, %{
        checkin_date: checkin1,
        checkout_date: checkout1,
        guests_count: min(2, room.capacity_max || 4),
        property: :tahoe,
        booking_mode: :room,
        room_id: room.id,
        user_id: user1.id
      })
      |> Ysc.Bookings.BookingValidator.validate(user: user1)
      |> Repo.insert(on_conflict: :nothing)

      # Second booking starts on day 15 (same-day turnaround - allowed due to check-in/check-out times)
      checkin2 = checkout1  # Same as checkout date of first booking
      checkout2 = Date.add(checkin2, 3)  # 3 nights (checkin < checkout)

      user2 = Enum.at(users, 1)
      Booking.changeset(%Booking{}, %{
        checkin_date: checkin2,
        checkout_date: checkout2,
        guests_count: min(3, room.capacity_max || 4),
        property: :tahoe,
        booking_mode: :room,
        room_id: room.id,
        user_id: user2.id
      })
      |> Ysc.Bookings.BookingValidator.validate(user: user2)
      |> Repo.insert(on_conflict: :nothing)
    end

    # Booking 4: Overlapping booking (to show conflicts - these will fail validation)
    # Note: These are intentionally overlapping to demonstrate validation errors
    if Enum.count(users) > 3 && Enum.count(tahoe_rooms) > 3 do
      room = Enum.at(tahoe_rooms, 3)

      checkin1 = Date.add(base_date, 20)
      checkout1 = Date.add(checkin1, 3)  # 3 nights (checkin < checkout)

      user1 = Enum.at(users, 3)
      Booking.changeset(%Booking{}, %{
        checkin_date: checkin1,
        checkout_date: checkout1,
        guests_count: min(2, room.capacity_max || 4),
        property: :tahoe,
        booking_mode: :room,
        room_id: room.id,
        user_id: user1.id
      })
      |> Ysc.Bookings.BookingValidator.validate(user: user1)
      |> Repo.insert(on_conflict: :nothing)

      # Overlapping booking (conflicts with the one above - this will fail validation)
      checkin2 = Date.add(base_date, 22)
      checkout2 = Date.add(checkin2, 3)  # 3 nights (checkin < checkout)

      user2 = Enum.at(users, 0)
      Booking.changeset(%Booking{}, %{
        checkin_date: checkin2,
        checkout_date: checkout2,
        guests_count: min(1, room.capacity_max || 4),
        property: :tahoe,
        booking_mode: :room,
        room_id: room.id,
        user_id: user2.id
      })
      |> Ysc.Bookings.BookingValidator.validate(user: user2)
      |> Repo.insert(on_conflict: :nothing)
    end

    # Booking 5: Different room, same dates
    if Enum.count(users) > 4 && Enum.count(tahoe_rooms) > 4 do
      checkin = Date.add(base_date, 25)
      checkout = Date.add(checkin, 3)  # 3 nights (checkin < checkout)

      user = Enum.at(users, 4)
      room = Enum.at(tahoe_rooms, 4)

      Booking.changeset(%Booking{}, %{
        checkin_date: checkin,
        checkout_date: checkout,
        guests_count: min(4, room.capacity_max || 4),
        property: :tahoe,
        booking_mode: :room,
        room_id: room.id,
        user_id: user.id
      })
      |> BookingValidator.validate(user: user)
      |> Repo.insert(on_conflict: :nothing)
    end

    IO.puts("Created sample bookings")
  end
end

IO.puts("Booking seeds completed successfully!")
IO.puts("Created:")
IO.puts("  - 3 room categories")
IO.puts("  - 4 seasons (2 per property)")
IO.puts("  - 8 Tahoe rooms")
IO.puts("  - 6 pricing rules")
IO.puts("  - Sample bookings for visualization")
