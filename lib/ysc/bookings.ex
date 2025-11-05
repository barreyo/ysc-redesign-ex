defmodule Ysc.Bookings do
  @moduledoc """
  Context module for managing bookings, seasons, rooms, and pricing rules.

  ## Booking Rules

  - **Check-in Time**: 3:00 PM (15:00)
  - **Check-out Time**: 11:00 AM (11:00)

  These times allow same-day turnarounds: a booking ending on a date
  (check-out at 11 AM) can be followed by another booking starting on the same
  date (check-in at 3 PM), with a 4-hour gap for cleaning/preparation.

  Example:
  - Booking 1: Nov 1 - Nov 3 (checks out Nov 3 at 11 AM)
  - Booking 2: Nov 3 - Nov 5 (checks in Nov 3 at 3 PM)
  - These bookings do NOT overlap and can both be accepted.
  """
  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.Bookings.{Season, PricingRule, Room, RoomCategory, Blackout, Booking, DoorCode}

  # Check-in and check-out times
  @checkin_time ~T[15:00:00]
  @checkout_time ~T[11:00:00]

  ## Seasons

  @doc """
  Lists all seasons, optionally filtered by property.
  """
  def list_seasons(property \\ nil) do
    query = from s in Season, order_by: [asc: s.property, asc: s.name]

    query =
      if property do
        from s in query, where: s.property == ^property
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets a single season.
  """
  def get_season!(id) do
    Repo.get!(Season, id)
  end

  @doc """
  Creates a season.
  """
  def create_season(attrs \\ %{}) do
    %Season{}
    |> Season.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a season.
  """
  def update_season(%Season{} = season, attrs) do
    season
    |> Season.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a season.
  """
  def delete_season(%Season{} = season) do
    Repo.delete(season)
  end

  ## Pricing Rules

  @doc """
  Lists all pricing rules, with preloaded associations.
  """
  def list_pricing_rules do
    from(pr in PricingRule,
      order_by: [asc: pr.property, asc: pr.booking_mode, asc: pr.price_unit],
      preload: [:room, :room_category, :season]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single pricing rule.
  """
  def get_pricing_rule!(id) do
    Repo.get!(PricingRule, id)
    |> Repo.preload([:room, :room_category, :season])
  end

  @doc """
  Creates a pricing rule.
  """
  def create_pricing_rule(attrs \\ %{}) do
    %PricingRule{}
    |> PricingRule.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a pricing rule.
  """
  def update_pricing_rule(%PricingRule{} = pricing_rule, attrs) do
    pricing_rule
    |> PricingRule.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a pricing rule.
  """
  def delete_pricing_rule(%PricingRule{} = pricing_rule) do
    Repo.delete(pricing_rule)
  end

  ## Rooms

  @doc """
  Lists all rooms, optionally filtered by property.
  """
  def list_rooms(property \\ nil) do
    query = from r in Room, order_by: [asc: r.property, asc: r.name], preload: [:room_category]

    query =
      if property do
        from r in query, where: r.property == ^property
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets a single room.
  """
  def get_room!(id) do
    Repo.get!(Room, id)
    |> Repo.preload(:room_category)
  end

  ## Room Categories

  @doc """
  Lists all room categories.
  """
  def list_room_categories do
    Repo.all(from rc in RoomCategory, order_by: [asc: rc.name])
  end

  ## Bookings

  @doc """
  Lists all bookings, optionally filtered by property and date range.

  A booking is included if it overlaps with the date range, meaning:
  - The booking's check-in date is <= end_date
  - The booking's checkout date is >= start_date

  ## Parameters
  - `property`: Optional atom property filter (e.g., `:tahoe`, `:clear_lake`)
  - `start_date`: Optional start date for filtering (inclusive)
  - `end_date`: Optional end date for filtering (inclusive)

  ## Examples
      # Get all bookings for Tahoe
      list_bookings(:tahoe)

      # Get bookings for Tahoe in November 2025
      list_bookings(:tahoe, ~D[2025-11-01], ~D[2025-11-30])

      # Get all bookings in a date range across all properties
      list_bookings(nil, ~D[2025-11-01], ~D[2025-11-30])
  """
  def list_bookings(property \\ nil, start_date \\ nil, end_date \\ nil) do
    query = from b in Booking, order_by: [asc: b.checkin_date], preload: [:room, :user]

    query =
      if property do
        from b in query, where: b.property == ^property
      else
        query
      end

    query =
      if start_date && end_date do
        from b in query,
          where:
            fragment(
              "(? <= ? AND ? >= ?)",
              b.checkin_date,
              ^end_date,
              b.checkout_date,
              ^start_date
            )
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Lists bookings with pagination, filtering, and search support.

  Supports fuzzy search by user name, email, or booking reference.
  Supports date range filtering by booking dates.
  """
  def list_paginated_bookings(params) do
    # Extract date range filters if present
    {date_range_filters, other_params} = extract_date_range_filters(params)
    # Extract property filter if present
    {property_filter, other_params} = extract_property_filter(other_params)

    base_query = from(b in Booking, preload: [:user, room: :room_category])

    # Apply property filter
    base_query =
      if property_filter do
        from b in base_query, where: b.property == ^property_filter
      else
        base_query
      end

    # Apply date range filters
    base_query =
      if date_range_filters[:filter_start_date] && date_range_filters[:filter_end_date] do
        from b in base_query,
          where:
            fragment(
              "(? <= ? AND ? >= ?)",
              b.checkin_date,
              ^date_range_filters[:filter_end_date],
              b.checkout_date,
              ^date_range_filters[:filter_start_date]
            )
      else
        base_query
      end

    case Flop.validate_and_run(base_query, other_params, for: Booking) do
      {:ok, {bookings, meta}} ->
        {:ok, {bookings, meta}}

      error ->
        error
    end
  end

  def list_paginated_bookings(params, nil), do: list_paginated_bookings(params)

  def list_paginated_bookings(params, search_term) when search_term == "",
    do: list_paginated_bookings(params)

  @spec list_paginated_bookings(
          %{optional(:__struct__) => Flop, optional(atom() | binary()) => any()},
          any()
        ) :: {:error, Flop.Meta.t()} | {:ok, {list(), Flop.Meta.t()}}
  def list_paginated_bookings(params, search_term) do
    # Extract date range filters if present
    {date_range_filters, other_params} = extract_date_range_filters(params)
    # Extract property filter if present
    {property_filter, other_params} = extract_property_filter(other_params)

    base_query = fuzzy_search_booking(search_term)

    # Apply property filter
    base_query =
      if property_filter do
        from b in base_query, where: b.property == ^property_filter
      else
        base_query
      end

    # Apply date range filters
    base_query =
      if date_range_filters[:filter_start_date] && date_range_filters[:filter_end_date] do
        from b in base_query,
          where:
            fragment(
              "(? <= ? AND ? >= ?)",
              b.checkin_date,
              ^date_range_filters[:filter_end_date],
              b.checkout_date,
              ^date_range_filters[:filter_start_date]
            )
      else
        base_query
      end

    case Flop.validate_and_run(base_query, other_params, for: Booking) do
      {:ok, {bookings, meta}} ->
        {:ok, {bookings, meta}}

      error ->
        error
    end
  end

  defp fuzzy_search_booking(search_term) do
    search_like = "%#{search_term}%"

    from(b in Booking,
      left_join: u in assoc(b, :user),
      where:
        fragment("SIMILARITY(?, ?) > 0.2", u.email, ^search_term) or
          fragment("SIMILARITY(?, ?) > 0.2", u.first_name, ^search_term) or
          fragment("SIMILARITY(?, ?) > 0.2", u.last_name, ^search_term) or
          ilike(b.reference_id, ^search_like),
      preload: [:user, room: :room_category]
    )
  end

  defp extract_property_filter(params) do
    if params["filter"] && params["filter"]["property"] do
      property_str = params["filter"]["property"]
      property_atom = String.to_existing_atom(property_str)
      filtered_params = delete_in(params, ["filter", "property"])
      {property_atom, filtered_params}
    else
      {nil, params}
    end
  end

  defp extract_date_range_filters(params) do
    filter_start_date =
      if params["filter"] && params["filter"]["filter_start_date"] do
        case Date.from_iso8601(params["filter"]["filter_start_date"]) do
          {:ok, date} -> date
          _ -> nil
        end
      else
        nil
      end

    filter_end_date =
      if params["filter"] && params["filter"]["filter_end_date"] do
        case Date.from_iso8601(params["filter"]["filter_end_date"]) do
          {:ok, date} -> date
          _ -> nil
        end
      else
        nil
      end

    filtered_params =
      params
      |> delete_in(["filter", "filter_start_date"])
      |> delete_in(["filter", "filter_end_date"])

    {%{filter_start_date: filter_start_date, filter_end_date: filter_end_date}, filtered_params}
  end

  defp delete_in(map, [key | rest]) when is_map(map) do
    case rest do
      [] ->
        Map.delete(map, key)

      [next_key | remaining] ->
        if is_map(map[key]) do
          Map.update(map, key, %{}, fn nested_map ->
            delete_in(nested_map, [next_key | remaining])
          end)
        else
          map
        end
    end
  end

  defp delete_in(map, _), do: map

  @doc """
  Gets a single booking.
  """
  def get_booking!(id) do
    Repo.get!(Booking, id)
    |> Repo.preload([:room, :user])
  end

  @doc """
  Creates a booking.
  """
  def create_booking(attrs \\ %{}) do
    %Booking{}
    |> Booking.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a booking.
  """
  def update_booking(%Booking{} = booking, attrs) do
    booking
    |> Booking.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a booking.
  """
  def delete_booking(%Booking{} = booking) do
    Repo.delete(booking)
  end

  ## Blackouts

  @doc """
  Lists all blackouts, optionally filtered by property and date range.

  A blackout is included if it overlaps with the date range, meaning:
  - The blackout's start_date is <= end_date
  - The blackout's end_date is >= start_date

  ## Parameters
  - `property`: Optional atom property filter (e.g., `:tahoe`, `:clear_lake`)
  - `start_date`: Optional start date for filtering (inclusive)
  - `end_date`: Optional end date for filtering (inclusive)

  ## Examples
      # Get all blackouts for Tahoe
      list_blackouts(:tahoe)

      # Get blackouts for Tahoe in November 2025
      list_blackouts(:tahoe, ~D[2025-11-01], ~D[2025-11-30])

      # Get all blackouts in a date range across all properties
      list_blackouts(nil, ~D[2025-11-01], ~D[2025-11-30])
  """
  def list_blackouts(property \\ nil, start_date \\ nil, end_date \\ nil) do
    query = from b in Blackout, order_by: [asc: b.property, asc: b.start_date]

    query =
      if property do
        from b in query, where: b.property == ^property
      else
        query
      end

    query =
      if start_date && end_date do
        from b in query,
          where:
            fragment(
              "(? <= ? AND ? >= ?)",
              b.start_date,
              ^end_date,
              b.end_date,
              ^start_date
            )
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets a single blackout.
  """
  def get_blackout!(id) do
    Repo.get!(Blackout, id)
  end

  @doc """
  Creates a blackout.
  """
  def create_blackout(attrs \\ %{}) do
    %Blackout{}
    |> Blackout.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a blackout.
  """
  def update_blackout(%Blackout{} = blackout, attrs) do
    blackout
    |> Blackout.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a blackout.
  """
  def delete_blackout(%Blackout{} = blackout) do
    Repo.delete(blackout)
  end

  @doc """
  Checks if a date range overlaps with any blackouts for a property.

  Returns true if there's a blackout that would block the given date range.
  """
  def has_blackout?(property, start_date, end_date) when is_atom(property) do
    query =
      from b in Blackout,
        where: b.property == ^property,
        where:
          fragment(
            "(? <= ? AND ? >= ?)",
            b.start_date,
            ^end_date,
            b.end_date,
            ^start_date
          )

    Repo.exists?(query)
  end

  @doc """
  Gets all blackouts that overlap with a date range for a property.
  """
  def get_overlapping_blackouts(property, start_date, end_date) when is_atom(property) do
    from(b in Blackout,
      where: b.property == ^property,
      where:
        fragment(
          "(? <= ? AND ? >= ?)",
          b.start_date,
          ^end_date,
          b.end_date,
          ^start_date
        ),
      order_by: [asc: b.start_date]
    )
    |> Repo.all()
  end

  ## Booking Availability

  @doc """
  Checks if two booking date ranges overlap, accounting for check-in/check-out times.

  Since check-out is at 11 AM and check-in is at 3 PM, bookings can share the
  same date if one ends and the other starts on that date.

  ## Parameters
  - `checkin_date1`, `checkout_date1`: First booking's dates
  - `checkin_date2`, `checkout_date2`: Second booking's dates

  ## Returns
  - `true` if the bookings overlap (conflict)
  - `false` if they don't overlap (can coexist)

  ## Examples
      iex> Ysc.Bookings.bookings_overlap?(~D[2025-11-01], ~D[2025-11-03], ~D[2025-11-03], ~D[2025-11-05])
      false
      # First booking ends Nov 3 at 11 AM, second starts Nov 3 at 3 PM - no overlap

      iex> Ysc.Bookings.bookings_overlap?(~D[2025-11-01], ~D[2025-11-04], ~D[2025-11-03], ~D[2025-11-05])
      true
      # First booking includes Nov 3 and Nov 4, second includes Nov 3 and Nov 4 - overlap

      iex> Ysc.Bookings.bookings_overlap?(~D[2025-11-01], ~D[2025-11-02], ~D[2025-11-02], ~D[2025-11-03])
      false
      # First ends Nov 2 at 11 AM, second starts Nov 2 at 3 PM - no overlap
  """
  def bookings_overlap?(checkin_date1, checkout_date1, checkin_date2, checkout_date2) do
    # Bookings overlap if:
    # 1. The first booking's check-in date is before the second's checkout date
    #    AND the first booking's checkout date is after the second's check-in date
    # 2. BUT we need to account for same-day turnarounds:
    #    - If one booking ends on date X and another starts on date X, they don't overlap
    #    - So we exclude the case where checkout_date1 == checkin_date2
    #    - And we exclude the case where checkout_date2 == checkin_date1

    cond do
      # Same-day turnarounds: if one ends and the other starts on the same date, no overlap
      checkout_date1 == checkin_date2 ->
        false

      checkout_date2 == checkin_date1 ->
        false

      # Otherwise, check for standard overlap
      # Overlap occurs if: checkin1 < checkout2 AND checkout1 > checkin2
      Date.compare(checkin_date1, checkout_date2) == :lt &&
          Date.compare(checkout_date1, checkin_date2) == :gt ->
        true

      true ->
        false
    end
  end

  @doc """
  Gets the check-in time (3:00 PM).
  """
  def checkin_time, do: @checkin_time

  @doc """
  Gets the check-out time (11:00 AM).
  """
  def checkout_time, do: @checkout_time

  @doc """
  Checks if a room is available for the given date range.

  A room is available if:
  - There are no existing bookings that overlap with the date range
  - There are no blackouts for the property that overlap with the date range
  - The room is active

  ## Parameters
  - `room_id`: The room to check
  - `checkin_date`: Check-in date
  - `checkout_date`: Check-out date
  - `exclude_booking_id`: Optional booking ID to exclude from the check (for updates)

  ## Returns
  - `true` if available
  - `false` if not available
  """
  def room_available?(room_id, checkin_date, checkout_date, exclude_booking_id \\ nil) do
    room = get_room!(room_id)

    if not room.is_active do
      false
    else
      # Check for overlapping bookings
      overlapping_bookings_query =
        from b in Booking,
          where: b.room_id == ^room_id,
          where:
            fragment(
              "(? < ? AND ? > ?)",
              b.checkin_date,
              ^checkout_date,
              b.checkout_date,
              ^checkin_date
            )

      overlapping_bookings_query =
        if exclude_booking_id do
          from b in overlapping_bookings_query, where: b.id != ^exclude_booking_id
        else
          overlapping_bookings_query
        end

      has_overlapping_bookings = Repo.exists?(overlapping_bookings_query)

      if has_overlapping_bookings do
        false
      else
        # Check for blackouts
        not has_blackout?(room.property, checkin_date, checkout_date)
      end
    end
  end

  @doc """
  Gets available rooms for a property and date range.

  Returns a list of rooms that are available for the given dates.
  """
  def get_available_rooms(property, checkin_date, checkout_date) do
    list_rooms(property)
    |> Enum.filter(fn room ->
      room_available?(room.id, checkin_date, checkout_date)
    end)
  end

  @doc """
  Calculates the total price for a booking.

  ## Parameters
  - `property`: The property (:tahoe or :clear_lake)
  - `checkin_date`: Check-in date
  - `checkout_date`: Check-out date
  - `booking_mode`: Booking mode (:room, :day, or :buyout)
  - `room_id`: Optional room ID (for room bookings)
  - `guests_count`: Number of guests/people
  - `exclude_booking_id`: Optional booking ID to exclude (for updates)

  ## Returns
  - `{:ok, %Money{}}` with the total price
  - `{:error, reason}` if pricing cannot be calculated
  """
  def calculate_booking_price(
        property,
        checkin_date,
        checkout_date,
        booking_mode,
        room_id \\ nil,
        guests_count \\ 1,
        children_count \\ 0,
        exclude_booking_id \\ nil
      ) do
    nights = Date.diff(checkout_date, checkin_date)

    if nights <= 0 do
      {:error, :invalid_date_range}
    else
      case booking_mode do
        :buyout ->
          calculate_buyout_price(property, checkin_date, checkout_date, nights)

        :room ->
          if room_id do
            calculate_room_price(
              property,
              checkin_date,
              checkout_date,
              room_id,
              guests_count,
              children_count,
              nights
            )
          else
            {:error, :room_id_required}
          end

        :day ->
          calculate_day_price(property, checkin_date, checkout_date, guests_count, nights)

        _ ->
          {:error, :invalid_booking_mode}
      end
    end
  end

  defp calculate_buyout_price(property, checkin_date, checkout_date, nights) do
    # For buyouts, we need to check the season for each night
    # and sum up the prices
    date_range = Date.range(checkin_date, Date.add(checkout_date, -1)) |> Enum.to_list()

    total =
      Enum.reduce(date_range, Money.new(0, :USD), fn date, acc ->
        season = Season.for_date(property, date)
        season_id = if season, do: season.id, else: nil

        pricing_rule =
          PricingRule.find_most_specific(
            property,
            season_id,
            nil,
            nil,
            :buyout,
            :buyout_fixed
          )

        if pricing_rule do
          case Money.add(acc, pricing_rule.amount) do
            {:ok, new_total} -> new_total
            {:error, _} -> acc
          end
        else
          acc
        end
      end)

    {:ok, total}
  end

  defp calculate_room_price(
         property,
         checkin_date,
         checkout_date,
         room_id,
         guests_count,
         children_count,
         nights
       ) do
    # Validate inputs before proceeding
    cond do
      not (is_integer(guests_count) && guests_count > 0) ->
        {:error, :invalid_guests_count}

      not (is_integer(children_count) && children_count >= 0) ->
        {:error, :invalid_children_count}

      not is_struct(checkin_date, Date) ->
        {:error, :invalid_checkin_date}

      not is_struct(checkout_date, Date) ->
        {:error, :invalid_checkout_date}

      Date.compare(checkout_date, checkin_date) != :gt ->
        {:error, :invalid_date_range}

      true ->
        room = get_room!(room_id)

        # Safely call billable_people with error handling
        billable_people =
          try do
            Room.billable_people(room, guests_count)
          rescue
            e ->
              # Log the error and return nil
              require Logger
              Logger.error("Error in billable_people for room #{room_id}: #{inspect(e)}")
              Logger.error("Room: #{inspect(room)}")
              Logger.error("guests_count: #{inspect(guests_count)}")
              nil
          end

        if not billable_people do
          {:error, :invalid_guests_count}
        else
          # Calculate price per night and sum
          # Validate dates before using Date functions
          try do
            date_range = Date.range(checkin_date, Date.add(checkout_date, -1)) |> Enum.to_list()

            total =
              Enum.reduce(date_range, Money.new(0, :USD), fn date, acc ->
                season = Season.for_date(property, date)
                season_id = if season, do: season.id, else: nil

                pricing_rule =
                  PricingRule.find_most_specific(
                    property,
                    season_id,
                    room_id,
                    room.room_category_id,
                    :room,
                    :per_person_per_night
                  )

                if pricing_rule do
                  # Calculate base price for adults (billable_people)
                  base_price =
                    case Money.mult(pricing_rule.amount, billable_people) do
                      {:ok, price} -> price
                      {:error, _} -> Money.new(0, :USD)
                    end

                  # For Tahoe: add children pricing ($25/night for children 5-17, free under 5)
                  # children_count represents children 5-17
                  children_price =
                    if property == :tahoe && children_count > 0 do
                      children_rate = Money.new(25, :USD)

                      case Money.mult(children_rate, children_count) do
                        {:ok, price} -> price
                        {:error, _} -> Money.new(0, :USD)
                      end
                    else
                      Money.new(0, :USD)
                    end

                  night_total =
                    case Money.add(base_price, children_price) do
                      {:ok, total} -> total
                      {:error, _} -> base_price
                    end

                  case Money.add(acc, night_total) do
                    {:ok, new_total} -> new_total
                    {:error, _} -> acc
                  end
                else
                  acc
                end
              end)

            {:ok, total}
          rescue
            e ->
              # Log date-related errors
              require Logger
              Logger.error("Error calculating date range for room #{room_id}: #{inspect(e)}")

              Logger.error(
                "checkin_date: #{inspect(checkin_date)}, checkout_date: #{inspect(checkout_date)}"
              )

              {:error, :date_calculation_error}
          end
        end
    end
  end

  defp calculate_day_price(property, checkin_date, checkout_date, guests_count, nights) do
    # For day bookings, price is per guest per day
    # Clear Lake uses this model
    pricing_rule =
      PricingRule.find_most_specific(property, nil, nil, nil, :day, :per_guest_per_day)

    if pricing_rule do
      total_days = nights
      total_guests = guests_count

      case Money.mult(pricing_rule.amount, total_days * total_guests) do
        {:ok, total} -> {:ok, total}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :pricing_rule_not_found}
    end
  end

  ## Door Codes

  @doc """
  Gets the currently active door code for a property.
  Returns nil if no active code exists.
  """
  def get_active_door_code(property) do
    from(dc in DoorCode,
      where: dc.property == ^property,
      where: is_nil(dc.active_to),
      order_by: [desc: dc.active_from],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Lists all door codes for a property, ordered by most recent first.
  """
  def list_door_codes(property) do
    from(dc in DoorCode,
      where: dc.property == ^property,
      order_by: [desc: dc.active_from, desc: dc.inserted_at],
      limit: 10
    )
    |> Repo.all()
  end

  @doc """
  Gets the last 3 door codes (excluding the current one if it matches) for a property.
  Used to check for code reuse warnings.
  """
  def get_recent_door_codes(property, exclude_code \\ nil) do
    query =
      from(dc in DoorCode,
        where: dc.property == ^property,
        order_by: [desc: dc.active_from, desc: dc.inserted_at],
        limit: 3
      )

    query =
      if exclude_code do
        from(dc in query, where: dc.code != ^exclude_code)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Creates a new door code and invalidates all previous codes for the property.

  Sets active_from to the current datetime and active_to to nil (making it active).
  Sets active_to to the current datetime for all other door codes for this property.
  """
  def create_door_code(attrs \\ %{}) do
    property = attrs[:property] || attrs["property"]
    code = attrs[:code] || attrs["code"]

    if is_nil(property) or is_nil(code) do
      {:error, :invalid_attributes}
    else
      case Repo.transaction(fn ->
             now = DateTime.utc_now()

             # Invalidate all previous door codes for this property
             from(dc in DoorCode,
               where: dc.property == ^property,
               where: is_nil(dc.active_to)
             )
             |> Repo.update_all(set: [active_to: now])

             # Create the new door code - normalize all keys to strings
             door_code_attrs =
               attrs
               |> Enum.map(fn
                 {k, v} when is_atom(k) -> {Atom.to_string(k), v}
                 {k, v} -> {k, v}
               end)
               |> Enum.into(%{})
               |> Map.put("active_from", now)
               |> Map.put("active_to", nil)
               |> Map.put("property", property)
               |> Map.put("code", code)

             case %DoorCode{}
                  |> DoorCode.changeset(door_code_attrs)
                  |> Repo.insert() do
               {:ok, door_code} ->
                 door_code

               {:error, changeset} ->
                 Repo.rollback(changeset)
             end
           end) do
        {:ok, door_code} ->
          {:ok, door_code}

        {:error, changeset} ->
          {:error, changeset}

        error ->
          error
      end
    end
  end

  @doc """
  Gets a single door code.
  """
  def get_door_code!(id) do
    Repo.get!(DoorCode, id)
  end
end
