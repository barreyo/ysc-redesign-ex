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
    is_default: false,
    advance_booking_days: 45 # Winter enforces 45-day limit
  }, [:name, :property])

# Note: We'll set summer as default since it's longer, but you can adjust
tahoe_summer =
  BookingSeeds.get_or_create(Season, %{
    name: "Summer",
    description: "Summer season for Tahoe cabin (May 1 - Oct 31, recurring annually)",
    property: :tahoe,
    start_date: summer_start,
    end_date: summer_end,
    is_default: true,
    advance_booking_days: nil # Summer allows booking as far out as desired (no limit)
  }, [:name, :property])

# Clear Lake seasons
clear_lake_winter =
  BookingSeeds.get_or_create(Season, %{
    name: "Winter",
    description: "Winter season for Clear Lake cabin (Nov 1 - Apr 30, recurring annually)",
    property: :clear_lake,
    start_date: winter_start,
    end_date: winter_end,
    is_default: false,
    advance_booking_days: nil # Clear Lake allows booking as far out as desired (no limit)
  }, [:name, :property])

clear_lake_summer =
  BookingSeeds.get_or_create(Season, %{
    name: "Summer",
    description: "Summer season for Clear Lake cabin (May 1 - Oct 31, recurring annually)",
    property: :clear_lake,
    start_date: summer_start,
    end_date: summer_end,
    is_default: true,
    advance_booking_days: nil # Clear Lake allows booking as far out as desired (no limit)
  }, [:name, :property])

# 3. Create Tahoe rooms
IO.puts("Creating Tahoe rooms...")

room_names = ["Room 1", "Room 2", "Room 3", "Room 4", "Room 5a", "Room 5b", "Room 6", "Room 7"]

tahoe_rooms =
  Enum.map(room_names, fn name ->
    room_attrs =
      cond do
        name == "Room 5a" ->
          # Single bed room
          %{
            name: name,
            description: "Cozy single bed room with 1 single bed. Perfect for solo travelers.",
            property: :tahoe,
            capacity_max: 1,
            min_billable_occupancy: 1,
            is_single_bed: true,
            single_beds: 1,
            queen_beds: 0,
            king_beds: 0,
            is_active: true,
            room_category_id: single_category.id,
            default_season_id: tahoe_summer.id
          }

        name == "Room 5b" ->
          # Single bed room
          %{
            name: name,
            description: "Cozy single bed room with 1 single bed. Perfect for solo travelers.",
            property: :tahoe,
            capacity_max: 1,
            min_billable_occupancy: 1,
            is_single_bed: true,
            single_beds: 1,
            queen_beds: 0,
            king_beds: 0,
            is_active: true,
            room_category_id: single_category.id,
            default_season_id: tahoe_summer.id
          }

        name == "Room 4" ->
          # Family room
          %{
            name: name,
            description: "Spacious family room with 1 queen bed and 3 single beds. Accommodates up to 5 guests. Minimum 2 guests required.",
            property: :tahoe,
            capacity_max: 5,
            min_billable_occupancy: 2,
            is_single_bed: false,
            single_beds: 3,
            queen_beds: 1,
            king_beds: 0,
            is_active: true,
            room_category_id: family_category.id,
            default_season_id: tahoe_summer.id
          }

        name == "Room 1" ->
          # Standard room - 2 guests
          %{
            name: name,
            description: "Comfortable room with 2 single beds. Perfect for two guests.",
            property: :tahoe,
            capacity_max: 2,
            min_billable_occupancy: 1,
            is_single_bed: false,
            single_beds: 2,
            queen_beds: 0,
            king_beds: 0,
            is_active: true,
            room_category_id: standard_category.id,
            default_season_id: tahoe_summer.id
          }

        name == "Room 2" ->
          # Standard room - 2 guests
          %{
            name: name,
            description: "Comfortable room with 1 queen bed. Ideal for couples or two guests.",
            property: :tahoe,
            capacity_max: 2,
            min_billable_occupancy: 1,
            is_single_bed: false,
            single_beds: 0,
            queen_beds: 1,
            king_beds: 0,
            is_active: true,
            room_category_id: standard_category.id,
            default_season_id: tahoe_summer.id
          }

        name == "Room 3" ->
          # Standard room - 2 guests
          %{
            name: name,
            description: "Comfortable room with 1 queen bed. Ideal for couples or two guests.",
            property: :tahoe,
            capacity_max: 2,
            min_billable_occupancy: 1,
            is_single_bed: false,
            single_beds: 0,
            queen_beds: 1,
            king_beds: 0,
            is_active: true,
            room_category_id: standard_category.id,
            default_season_id: tahoe_summer.id
          }

        name == "Room 6" ->
          # Standard room - 3 guests
          %{
            name: name,
            description: "Spacious room with 1 queen bed and 1 single bed. Accommodates up to 3 guests.",
            property: :tahoe,
            capacity_max: 3,
            min_billable_occupancy: 1,
            is_single_bed: false,
            single_beds: 1,
            queen_beds: 1,
            king_beds: 0,
            is_active: true,
            room_category_id: standard_category.id,
            default_season_id: tahoe_summer.id
          }

        name == "Room 7" ->
          # Standard room - 2 guests
          %{
            name: name,
            description: "Comfortable room with 1 queen bed. Ideal for couples or two guests.",
            property: :tahoe,
            capacity_max: 2,
            min_billable_occupancy: 1,
            is_single_bed: false,
            single_beds: 0,
            queen_beds: 1,
            king_beds: 0,
            is_active: true,
            room_category_id: standard_category.id,
            default_season_id: tahoe_summer.id
          }

        true ->
          # Default fallback (should not be reached)
          %{
            name: name,
            description: "Standard room",
            property: :tahoe,
            capacity_max: 2,
            min_billable_occupancy: 1,
            is_single_bed: false,
            single_beds: 0,
            queen_beds: 0,
            king_beds: 0,
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

# Get some users for bookings (need more for active + future bookings)
users = Repo.all(from u in User, where: u.state == :active, limit: 10)

if Enum.empty?(users) do
  IO.puts("Warning: No active users found. Please run seeds.exs first to create users.")
else
  # Get Tahoe rooms (need more for active + future bookings)
  tahoe_rooms = Repo.all(from r in Room, where: r.property == :tahoe and r.is_active == true)

  if Enum.empty?(tahoe_rooms) do
    IO.puts("Warning: No Tahoe rooms found.")
  else
    today = Date.utc_today()
    # Create bookings for the current and next month
    base_date = Date.beginning_of_month(today)

    # Active Booking 1: Currently active booking (started before today, ends after today)
    if Enum.count(users) > 0 && Enum.count(tahoe_rooms) > 0 do
      checkin = Date.add(today, -2)  # Started 2 days ago
      checkout = Date.add(today, 2)  # Ends 2 days from now

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
      |> BookingValidator.validate(user: user, skip_validation: true)
      |> Repo.insert(on_conflict: :nothing)
    end

    # Active Booking 2: Currently active booking (started yesterday, ends tomorrow)
    if Enum.count(users) > 1 && Enum.count(tahoe_rooms) > 1 do
      checkin = Date.add(today, -1)  # Started yesterday
      checkout = Date.add(today, 1)  # Ends tomorrow

      user = Enum.at(users, 1)
      room = Enum.at(tahoe_rooms, 1)

      Booking.changeset(%Booking{}, %{
        checkin_date: checkin,
        checkout_date: checkout,
        guests_count: min(2, room.capacity_max || 4),
        property: :tahoe,
        booking_mode: :room,
        room_id: room.id,
        user_id: user.id
      })
      |> BookingValidator.validate(user: user, skip_validation: true)
      |> Repo.insert(on_conflict: :nothing)
    end

    # Active Booking 3: Currently active booking (started 3 days ago, ends in 1 day)
    if Enum.count(users) > 2 && Enum.count(tahoe_rooms) > 2 do
      checkin = Date.add(today, -3)  # Started 3 days ago
      checkout = Date.add(today, 1)  # Ends tomorrow

      user = Enum.at(users, 2)
      room = Enum.at(tahoe_rooms, 2)

      Booking.changeset(%Booking{}, %{
        checkin_date: checkin,
        checkout_date: checkout,
        guests_count: min(3, room.capacity_max || 4),
        property: :tahoe,
        booking_mode: :room,
        room_id: room.id,
        user_id: user.id
      })
      |> BookingValidator.validate(user: user, skip_validation: true)
      |> Repo.insert(on_conflict: :nothing)
    end

    # Booking 4: One-night booking (minimum stay) - future booking
    if Enum.count(users) > 3 && Enum.count(tahoe_rooms) > 3 do
      checkin = Date.add(base_date, 5)
      checkout = Date.add(checkin, 1)  # At least 1 night (checkin < checkout)

      user = Enum.at(users, 3)
      room = Enum.at(tahoe_rooms, 3)

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

    # Booking 5: Multi-day booking (3 nights, max 4 for Tahoe) - future booking
    if Enum.count(users) > 4 && Enum.count(tahoe_rooms) > 4 do
      checkin = Date.add(base_date, 8)
      checkout = Date.add(checkin, 3)  # 3 nights

      user = Enum.at(users, 4)
      room = Enum.at(tahoe_rooms, 4)

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

    # Booking 6: Same-day turnaround (ends on date X, another starts on date X) - future booking
    if Enum.count(users) > 5 && Enum.count(tahoe_rooms) > 5 do
      room = Enum.at(tahoe_rooms, 5)

      # First booking ends on day 15
      checkin1 = Date.add(base_date, 13)
      checkout1 = Date.add(checkin1, 2)  # 2 nights (checkin < checkout)

      user1 = Enum.at(users, 5)
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

    # Booking 7: Different room, same dates - future booking
    if Enum.count(users) > 6 && Enum.count(tahoe_rooms) > 6 do
      checkin = Date.add(base_date, 25)
      checkout = Date.add(checkin, 3)  # 3 nights (checkin < checkout)

      user = Enum.at(users, 6)
      room = Enum.at(tahoe_rooms, 6)

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

    # Buyout bookings
    IO.puts("Creating buyout bookings...")

    # Get users that don't have active bookings yet (to avoid single active booking conflicts)
    # Use different users than the room bookings (indices 5+ to avoid conflicts)
    all_users = Repo.all(from u in User, where: u.state == :active, limit: 15)

    if Enum.count(all_users) >= 8 do
      # Tahoe Buyout 1: Summer buyout (2 nights, no weekend)
      # Must be in summer season (May 1 - Oct 31)
      today = Date.utc_today()
      current_year = today.year

      # Find a summer date that's within 45 days and doesn't conflict
      summer_start = Date.new!(current_year, 5, 1)
      summer_end = Date.new!(current_year, 10, 31)

      # Use a date that's in summer and within 45 days
      tahoe_buyout_checkin =
        if Date.compare(today, summer_start) == :lt do
          # If we're before summer, use summer start
          summer_start
        else
          # If we're in summer, use a date soon
          max_date = Date.add(today, 45)
          if Date.compare(summer_end, max_date) == :lt do
            Date.add(summer_end, -2)  # 2 days before summer ends
          else
            Date.add(today, 10)  # 10 days from now
          end
        end

      # Ensure it's a valid summer date
      tahoe_buyout_checkin =
        if Date.compare(tahoe_buyout_checkin, summer_start) == :lt do
          summer_start
        else
          if Date.compare(tahoe_buyout_checkin, summer_end) == :gt do
            Date.add(summer_end, -2)
          else
            tahoe_buyout_checkin
          end
        end

      tahoe_buyout_checkout = Date.add(tahoe_buyout_checkin, 2)  # 2 nights (max 4 allowed)

      # Make sure checkout is still in summer
      tahoe_buyout_checkout =
        if Date.compare(tahoe_buyout_checkout, summer_end) == :gt do
          summer_end
        else
          tahoe_buyout_checkout
        end

      # Use a user that doesn't have overlapping bookings (skip first 5 used for room bookings)
      tahoe_buyout_user = Enum.at(all_users, 5)

      Booking.changeset(%Booking{}, %{
        checkin_date: tahoe_buyout_checkin,
        checkout_date: tahoe_buyout_checkout,
        guests_count: 8,  # Can be any number for buyouts
        property: :tahoe,
        booking_mode: :buyout,
        room_id: nil,  # Buyouts don't have a specific room
        user_id: tahoe_buyout_user.id
      })
      |> BookingValidator.validate(user: tahoe_buyout_user)
      |> Repo.insert(on_conflict: :nothing)

      # Tahoe Buyout 2: Summer buyout with weekend (Saturday + Sunday)
      # Find a Saturday that's in summer and within 45 days
      tahoe_weekend_checkin =
        Enum.reduce_while(1..45, nil, fn days_ahead, _acc ->
          candidate_date = Date.add(today, days_ahead)
          day_of_week = Date.day_of_week(candidate_date, :monday)

          # Check if it's Saturday (6) and in summer
          if day_of_week == 6 and
             Date.compare(candidate_date, summer_start) != :lt and
             Date.compare(candidate_date, summer_end) != :gt do
            {:halt, candidate_date}
          else
            {:cont, nil}
          end
        end)

      if tahoe_weekend_checkin do
        # Saturday check-in, Sunday check-out (1 night, but includes both weekend days)
        tahoe_weekend_checkout = Date.add(tahoe_weekend_checkin, 1)  # Sunday

        # Ensure checkout is still in summer
        tahoe_weekend_checkout =
          if Date.compare(tahoe_weekend_checkout, summer_end) == :gt do
            # If checkout would be outside summer, adjust to stay within summer
            # But wait - if Saturday is the last day of summer, we can't have a valid weekend booking
            # In that case, skip this booking
            nil
          else
            tahoe_weekend_checkout
          end

        if tahoe_weekend_checkout do
          # Use a different user (skip first 5 used for room bookings)
          tahoe_weekend_user = Enum.at(all_users, 6)

          Booking.changeset(%Booking{}, %{
            checkin_date: tahoe_weekend_checkin,
            checkout_date: tahoe_weekend_checkout,
            guests_count: 10,
            property: :tahoe,
            booking_mode: :buyout,
            room_id: nil,
            user_id: tahoe_weekend_user.id
          })
          |> BookingValidator.validate(user: tahoe_weekend_user)
          |> Repo.insert(on_conflict: :nothing)
        end
      end

      # Tahoe Buyout 3: Maximum length buyout (4 nights)
      tahoe_max_checkin = Date.add(today, 15)  # 15 days ahead

      # Ensure it's in summer
      tahoe_max_checkin =
        if Date.compare(tahoe_max_checkin, summer_start) == :lt do
          summer_start
        else
          if Date.compare(tahoe_max_checkin, summer_end) == :gt do
            Date.add(summer_end, -4)  # 4 days before summer ends
          else
            tahoe_max_checkin
          end
        end

      tahoe_max_checkout = Date.add(tahoe_max_checkin, 4)  # 4 nights (max allowed)

      # Ensure checkout is still in summer
      tahoe_max_checkout =
        if Date.compare(tahoe_max_checkout, summer_end) == :gt do
          summer_end
        else
          tahoe_max_checkout
        end

      # Use a different user (skip first 5 used for room bookings)
      tahoe_max_user = Enum.at(all_users, 7)

      Booking.changeset(%Booking{}, %{
        checkin_date: tahoe_max_checkin,
        checkout_date: tahoe_max_checkout,
        guests_count: 12,
        property: :tahoe,
        booking_mode: :buyout,
        room_id: nil,
        user_id: tahoe_max_user.id
      })
      |> BookingValidator.validate(user: tahoe_max_user)
      |> Repo.insert(on_conflict: :nothing)

      # Clear Lake Buyout 1: Simple buyout
      clear_lake_buyout_checkin = Date.add(today, 12)
      clear_lake_buyout_checkout = Date.add(clear_lake_buyout_checkin, 2)  # 2 nights

      # Use a different user (skip first 5 used for room bookings)
      clear_lake_buyout_user = Enum.at(all_users, 5)

      Booking.changeset(%Booking{}, %{
        checkin_date: clear_lake_buyout_checkin,
        checkout_date: clear_lake_buyout_checkout,
        guests_count: 15,  # Can exceed 12 since it's a buyout
        property: :clear_lake,
        booking_mode: :buyout,
        room_id: nil,
        user_id: clear_lake_buyout_user.id
      })
      |> BookingValidator.validate(user: clear_lake_buyout_user)
      |> Repo.insert(on_conflict: :nothing)

      # Clear Lake Buyout 2: Longer buyout
      clear_lake_buyout2_checkin = Date.add(today, 20)
      clear_lake_buyout2_checkout = Date.add(clear_lake_buyout2_checkin, 5)  # 5 nights

      # Use a different user (skip first 5 used for room bookings)
      clear_lake_buyout2_user = Enum.at(all_users, 6)

      Booking.changeset(%Booking{}, %{
        checkin_date: clear_lake_buyout2_checkin,
        checkout_date: clear_lake_buyout2_checkout,
        guests_count: 20,
        property: :clear_lake,
        booking_mode: :buyout,
        room_id: nil,
        user_id: clear_lake_buyout2_user.id
      })
      |> BookingValidator.validate(user: clear_lake_buyout2_user)
      |> Repo.insert(on_conflict: :nothing)

      IO.puts("Created buyout bookings")
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
IO.puts("  - Sample room bookings for visualization")
IO.puts("  - Sample buyout bookings (Tahoe and Clear Lake)")
