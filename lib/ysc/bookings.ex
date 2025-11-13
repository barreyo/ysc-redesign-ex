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
  require Logger

  alias Ysc.Repo
  alias Stripe

  alias Ysc.Bookings.{
    Season,
    SeasonCache,
    PricingRule,
    Room,
    RoomCategory,
    Blackout,
    Booking,
    DoorCode,
    RefundPolicy,
    RefundPolicyRule,
    PendingRefund,
    PropertyInventory
  }

  # Check-in and check-out times
  @checkin_time ~T[15:00:00]
  @checkout_time ~T[11:00:00]

  ## Seasons

  @doc """
  Lists all seasons, optionally filtered by property.

  Uses cache when filtering by property for better performance.
  """
  def list_seasons(property \\ nil) do
    if property do
      # Use cache for property-specific lookups
      SeasonCache.get_all_for_property(property)
    else
      # For all seasons, query directly (less common, no cache needed)
      query = from s in Season, order_by: [asc: s.property, asc: s.name]
      Repo.all(query)
    end
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
    result =
      %Season{}
      |> Season.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, _season} ->
        # Invalidate season cache
        Ysc.Bookings.SeasonCache.invalidate()
        result

      _ ->
        result
    end
  end

  @doc """
  Updates a season.
  """
  def update_season(%Season{} = season, attrs) do
    result =
      season
      |> Season.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, _season} ->
        # Invalidate season cache
        Ysc.Bookings.SeasonCache.invalidate()
        result

      _ ->
        result
    end
  end

  @doc """
  Deletes a season.
  """
  def delete_season(%Season{} = season) do
    result = Repo.delete(season)

    case result do
      {:ok, _season} ->
        # Invalidate season cache
        Ysc.Bookings.SeasonCache.invalidate()
        result

      _ ->
        result
    end
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
    result =
      %PricingRule{}
      |> PricingRule.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, _pricing_rule} ->
        # Invalidate pricing rule cache
        Ysc.Bookings.PricingRuleCache.invalidate()
        result

      _ ->
        result
    end
  end

  @doc """
  Updates a pricing rule.
  """
  def update_pricing_rule(%PricingRule{} = pricing_rule, attrs) do
    result =
      pricing_rule
      |> PricingRule.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, _pricing_rule} ->
        # Invalidate pricing rule cache
        Ysc.Bookings.PricingRuleCache.invalidate()
        result

      _ ->
        result
    end
  end

  @doc """
  Deletes a pricing rule.
  """
  def delete_pricing_rule(%PricingRule{} = pricing_rule) do
    result = Repo.delete(pricing_rule)

    case result do
      {:ok, _pricing_rule} ->
        # Invalidate pricing rule cache
        Ysc.Bookings.PricingRuleCache.invalidate()
        result

      _ ->
        result
    end
  end

  ## Rooms

  @doc """
  Lists all rooms, optionally filtered by property.
  """
  def list_rooms(property \\ nil) do
    query =
      from r in Room, order_by: [asc: r.property, asc: r.name], preload: [:room_category, :image]

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
  def list_bookings(property \\ nil, start_date \\ nil, end_date \\ nil, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [:rooms, :user])
    query = from b in Booking, order_by: [asc: b.checkin_date], preload: ^preloads

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

    base_query = from(b in Booking, preload: [:user, rooms: :room_category])

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

  @doc """
  Lists paginated bookings for a specific user with Flop.
  """
  def list_user_bookings_paginated(user_id, params) do
    base_query =
      from(b in Booking,
        where: b.user_id == ^user_id,
        preload: [:user, rooms: :room_category]
      )

    case Flop.validate_and_run(base_query, params, for: Booking) do
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
      preload: [:user, rooms: :room_category]
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
    |> Repo.preload([:rooms, :user])
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
      # Check for overlapping bookings using the booking_rooms join table
      # ULIDs are stored as binary UUIDs in PostgreSQL, but have different string representations
      # We need to compare the binary UUID column with the ULID string
      # Since ULIDs are binary-compatible with UUIDs, we can use the room's ID directly
      # and let Ecto handle the conversion by using type/2 to specify binary_id
      overlapping_bookings_query =
        from b in Booking,
          join: br in "booking_rooms",
          on: br.booking_id == b.id,
          where: br.room_id == type(^room.id, Ecto.ULID),
          where:
            fragment(
              "(? < ? AND ? > ?)",
              b.checkin_date,
              ^checkout_date,
              b.checkout_date,
              ^checkin_date
            ),
          where: b.status in [:hold, :complete]

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
        _exclude_booking_id \\ nil,
        use_actual_guests \\ false
      ) do
    # Validate dates before using Date.diff
    cond do
      not is_struct(checkin_date, Date) ->
        Logger.error(
          "[Bookings] calculate_booking_price: invalid checkin_date: #{inspect(checkin_date)}"
        )

        {:error, :invalid_checkin_date}

      not is_struct(checkout_date, Date) ->
        Logger.error(
          "[Bookings] calculate_booking_price: invalid checkout_date: #{inspect(checkout_date)}"
        )

        {:error, :invalid_checkout_date}

      true ->
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
                  nights,
                  use_actual_guests
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
  end

  defp calculate_buyout_price(property, checkin_date, checkout_date, _nights) do
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
         nights,
         use_actual_guests \\ false
       ) do
    # Basic validation
    cond do
      not is_atom(property) ->
        {:error, :invalid_property}

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
        calculate_room_price_impl(
          property,
          checkin_date,
          checkout_date,
          room_id,
          guests_count,
          children_count,
          nights,
          use_actual_guests
        )
    end
  end

  defp calculate_room_price_impl(
         property,
         checkin_date,
         checkout_date,
         room_id,
         guests_count,
         children_count,
         _nights,
         use_actual_guests \\ false
       ) do
    room = get_room!(room_id)

    # For multiple rooms, use actual guests_count; for single room, use billable_people (capped by capacity)
    billable_people =
      if use_actual_guests do
        guests_count
      else
        Room.billable_people(room, guests_count) || guests_count
      end

    if is_nil(billable_people) or billable_people <= 0 do
      {:error, :invalid_guests_count}
    else
      date_range = Date.range(checkin_date, Date.add(checkout_date, -1)) |> Enum.to_list()

      {total, base_total, children_total, adult_price_per_night, children_price_per_night,
       found_pricing_rules} =
        Enum.reduce(
          date_range,
          {Money.new(0, :USD), Money.new(0, :USD), Money.new(0, :USD), nil, nil, false},
          fn date, {acc, base_acc, children_acc, adult_price, children_price, found_any} ->
            season = Season.for_date(property, date)
            season_id = if season, do: season.id, else: nil

            # Simple fallback hierarchy:
            # 1. Try room-specific pricing rule (booking_mode = :room)
            # 2. Try category-level pricing rule (booking_mode = :room)
            # 3. Try property-level buyout pricing (as fallback)
            pricing_rule =
              PricingRule.find_most_specific(
                property,
                season_id,
                room_id,
                room.room_category_id,
                :room,
                :per_person_per_night
              ) ||
                PricingRule.find_most_specific(
                  property,
                  season_id,
                  nil,
                  room.room_category_id,
                  :room,
                  :per_person_per_night
                ) ||
                PricingRule.find_most_specific(
                  property,
                  season_id,
                  nil,
                  nil,
                  :buyout,
                  :buyout_fixed
                )

            if pricing_rule do
              # Store per-person-per-night price (use first one found)
              adult_price = adult_price || pricing_rule.amount

              # Calculate base price
              {:ok, base_price} = Money.mult(pricing_rule.amount, billable_people)

              # Look up children pricing rule using same hierarchy
              # Falls back to $25 if no children pricing rule found
              children_pricing_rule =
                PricingRule.find_children_pricing_rule(
                  property,
                  season_id,
                  room_id,
                  room.room_category_id,
                  :room,
                  :per_person_per_night
                ) ||
                  PricingRule.find_children_pricing_rule(
                    property,
                    season_id,
                    nil,
                    room.room_category_id,
                    :room,
                    :per_person_per_night
                  ) ||
                  PricingRule.find_children_pricing_rule(
                    property,
                    season_id,
                    nil,
                    nil,
                    :room,
                    :per_person_per_night
                  )

              # Use children_amount from rule if found, otherwise fallback to $25
              children_price_per_person =
                if children_pricing_rule && children_pricing_rule.children_amount do
                  children_pricing_rule.children_amount
                else
                  Money.new(25, :USD)
                end

              # Store children price per night (use first one found)
              children_price = children_price || children_price_per_person

              # Add children pricing for Tahoe
              children_price_for_night =
                if property == :tahoe && children_count > 0 do
                  {:ok, price} = Money.mult(children_price_per_person, children_count)
                  price
                else
                  Money.new(0, :USD)
                end

              {:ok, night_total} = Money.add(base_price, children_price_for_night)
              {:ok, new_total} = Money.add(acc, night_total)
              {:ok, new_base_total} = Money.add(base_acc, base_price)
              {:ok, new_children_total} = Money.add(children_acc, children_price_for_night)
              {new_total, new_base_total, new_children_total, adult_price, children_price, true}
            else
              {acc, base_acc, children_acc, adult_price, children_price, found_any}
            end
          end
        )

      if not found_pricing_rules do
        {:error, :pricing_rule_not_found}
      else
        nights = length(date_range)

        base_per_night =
          if nights > 0 do
            {:ok, price} = Money.div(base_total, nights)
            price
          else
            Money.new(0, :USD)
          end

        children_per_night =
          if nights > 0 do
            {:ok, price} = Money.div(children_total, nights)
            price
          else
            Money.new(0, :USD)
          end

        # Ensure children_price_per_night has a fallback value
        children_price_per_night =
          children_price_per_night || Money.new(25, :USD)

        {:ok, total,
         %{
           base: base_total,
           children: children_total,
           base_per_night: base_per_night,
           children_per_night: children_per_night,
           nights: nights,
           billable_people: billable_people,
           guests_count: guests_count,
           children_count: children_count,
           adult_price_per_night: adult_price_per_night,
           children_price_per_night: children_price_per_night
         }}
      end
    end
  end

  defp calculate_day_price(property, _checkin_date, _checkout_date, guests_count, nights) do
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

  ## Refund Policies

  @doc """
  Lists all refund policies, optionally filtered by property and booking mode.
  """
  def list_refund_policies(property \\ nil, booking_mode \\ nil) do
    query = from rp in RefundPolicy, order_by: [asc: rp.property, asc: rp.booking_mode]

    query =
      if property do
        from rp in query, where: rp.property == ^property
      else
        query
      end

    query =
      if booking_mode do
        from rp in query, where: rp.booking_mode == ^booking_mode
      else
        query
      end

    policies = Repo.all(query)

    # Load rules for each policy, ordered by days_before_checkin descending
    Enum.map(policies, fn policy ->
      rules =
        from(r in RefundPolicyRule,
          where: r.refund_policy_id == ^policy.id
        )
        |> RefundPolicyRule.ordered_by_days()
        |> Repo.all()

      %{policy | rules: rules}
    end)
  end

  @doc """
  Gets a single refund policy.
  """
  def get_refund_policy!(id) do
    Repo.get!(RefundPolicy, id)
    |> Repo.preload(:rules)
  end

  @doc """
  Gets the active refund policy for a property and booking mode.
  Returns nil if no active policy exists.

  Uses cache for improved performance.
  """
  def get_active_refund_policy(property, booking_mode) do
    alias Ysc.Bookings.RefundPolicyCache
    RefundPolicyCache.get_active(property, booking_mode)
  end

  @doc """
  Creates a refund policy.
  """
  def create_refund_policy(attrs \\ %{}) do
    result =
      %RefundPolicy{}
      |> RefundPolicy.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, _refund_policy} ->
        # Invalidate refund policy cache
        Ysc.Bookings.RefundPolicyCache.invalidate()
        result

      _ ->
        result
    end
  end

  @doc """
  Creates a refund policy (bang version).
  """
  def create_refund_policy!(attrs \\ %{}) do
    result =
      %RefundPolicy{}
      |> RefundPolicy.changeset(attrs)
      |> Repo.insert!()

    # Invalidate refund policy cache
    Ysc.Bookings.RefundPolicyCache.invalidate()
    result
  end

  @doc """
  Updates a refund policy.
  """
  def update_refund_policy(%RefundPolicy{} = refund_policy, attrs) do
    result =
      refund_policy
      |> RefundPolicy.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, _refund_policy} ->
        # Invalidate refund policy cache
        Ysc.Bookings.RefundPolicyCache.invalidate()
        result

      _ ->
        result
    end
  end

  @doc """
  Deletes a refund policy.
  """
  def delete_refund_policy(%RefundPolicy{} = refund_policy) do
    result = Repo.delete(refund_policy)

    case result do
      {:ok, _refund_policy} ->
        # Invalidate refund policy cache
        Ysc.Bookings.RefundPolicyCache.invalidate()
        result

      _ ->
        result
    end
  end

  ## Refund Policy Rules

  @doc """
  Lists all rules for a refund policy, ordered by days_before_checkin descending.
  """
  def list_refund_policy_rules(refund_policy_id) do
    from(r in RefundPolicyRule,
      where: r.refund_policy_id == ^refund_policy_id
    )
    |> RefundPolicyRule.ordered_by_days()
    |> Repo.all()
  end

  @doc """
  Gets a single refund policy rule.
  """
  def get_refund_policy_rule!(id) do
    Repo.get!(RefundPolicyRule, id)
  end

  @doc """
  Creates a refund policy rule.
  """
  def create_refund_policy_rule(attrs \\ %{}) do
    result =
      %RefundPolicyRule{}
      |> RefundPolicyRule.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, _refund_policy_rule} ->
        # Invalidate refund policy cache (rules are part of the policy)
        Ysc.Bookings.RefundPolicyCache.invalidate()
        result

      _ ->
        result
    end
  end

  @doc """
  Creates a refund policy rule (bang version).
  """
  def create_refund_policy_rule!(attrs \\ %{}) do
    result =
      %RefundPolicyRule{}
      |> RefundPolicyRule.changeset(attrs)
      |> Repo.insert!()

    # Invalidate refund policy cache (rules are part of the policy)
    Ysc.Bookings.RefundPolicyCache.invalidate()
    result
  end

  @doc """
  Updates a refund policy rule.
  """
  def update_refund_policy_rule(%RefundPolicyRule{} = refund_policy_rule, attrs) do
    result =
      refund_policy_rule
      |> RefundPolicyRule.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, _refund_policy_rule} ->
        # Invalidate refund policy cache (rules are part of the policy)
        Ysc.Bookings.RefundPolicyCache.invalidate()
        result

      _ ->
        result
    end
  end

  @doc """
  Deletes a refund policy rule.
  """
  def delete_refund_policy_rule(%RefundPolicyRule{} = refund_policy_rule) do
    result = Repo.delete(refund_policy_rule)

    case result do
      {:ok, _refund_policy_rule} ->
        # Invalidate refund policy cache (rules are part of the policy)
        Ysc.Bookings.RefundPolicyCache.invalidate()
        result

      _ ->
        result
    end
  end

  ## Refund Calculation

  @doc """
  Calculates the refund amount for a booking based on the cancellation date and refund policy.

  ## Parameters
  - `booking`: The booking to calculate refund for
  - `cancellation_date`: The date the booking is being cancelled (defaults to today)

  ## Returns
  - `{:ok, refund_amount, applied_rule}` if a policy exists and calculation succeeds
  - `{:ok, full_refund, nil}` if no policy exists (full refund by default)
  - `{:error, reason}` if calculation fails

  ## Examples
      iex> booking = %Booking{property: :tahoe, booking_mode: :buyout, checkin_date: ~D[2025-12-01]}
      iex> calculate_refund(booking, ~D[2025-11-10])
      {:ok, %Money{amount: 500, currency: :USD}, %RefundPolicyRule{}}
  """
  def calculate_refund(booking, cancellation_date \\ Date.utc_today()) do
    policy = get_active_refund_policy(booking.property, booking.booking_mode)

    if is_nil(policy) or is_nil(policy.rules) or Enum.empty?(policy.rules) do
      # No policy exists - default to full refund
      {:ok, nil, nil}
    else
      days_before_checkin = Date.diff(booking.checkin_date, cancellation_date)

      if days_before_checkin < 0 do
        # Cancellation is after check-in date - no refund
        {:ok, Money.new(0, :USD), nil}
      else
        # Find the most restrictive rule that applies
        # Rules are ordered by days_before_checkin DESC, so we need to find
        # the rule with the smallest days_before_checkin where cancellation_days <= rule.days_before_checkin
        # This means we want the LAST rule in the list that matches (most restrictive)
        matching_rules =
          Enum.filter(policy.rules, fn rule ->
            days_before_checkin <= rule.days_before_checkin
          end)

        applied_rule =
          if Enum.empty?(matching_rules) do
            nil
          else
            # Get the rule with the smallest days_before_checkin (most restrictive)
            Enum.min_by(matching_rules, fn rule -> rule.days_before_checkin end)
          end

        if applied_rule do
          # Get the original payment amount for this booking
          case get_booking_payment_amount(booking) do
            {:ok, original_amount} ->
              refund_percentage = Decimal.to_float(applied_rule.refund_percentage)
              refund_amount = calculate_refund_amount(original_amount, refund_percentage)
              {:ok, refund_amount, applied_rule}

            {:error, reason} ->
              {:error, reason}
          end
        else
          # No rule applies - default to full refund
          {:ok, nil, nil}
        end
      end
    end
  end

  @doc """
  Gets the payment amount for a booking by looking up ledger entries.
  """
  def get_booking_payment_amount(booking) do
    import Ecto.Query

    # Find ledger entries for this booking
    # Note: We filter by amount > 0 in Elixir since Money comparison in queries is complex
    entries =
      from(e in Ysc.Ledgers.LedgerEntry,
        where: e.related_entity_type == ^:booking,
        where: e.related_entity_id == ^booking.id,
        order_by: [desc: e.inserted_at]
      )
      |> Repo.all()

    # Filter for positive amounts and get the first one
    entry =
      entries
      |> Enum.find(fn e ->
        e.amount && Money.positive?(e.amount)
      end)

    if entry do
      {:ok, entry.amount}
    else
      {:error, :payment_not_found}
    end
  end

  defp calculate_refund_amount(original_amount, refund_percentage)
       when is_float(refund_percentage) do
    # Convert percentage to decimal (e.g., 50.0 -> 0.5)
    multiplier = Decimal.from_float(refund_percentage / 100.0)

    case Money.mult(original_amount, multiplier) do
      {:ok, refund_amount} -> refund_amount
      {:error, _} -> Money.new(0, :USD)
    end
  end

  @doc """
  Cancels a booking and processes the refund according to the refund policy.

  If the refund is 100% (full refund), it processes immediately.
  If the refund is less than 100% (partial refund), it creates a pending refund
  that requires admin review.

  ## Parameters
  - `booking`: The booking to cancel
  - `cancellation_date`: Optional cancellation date (defaults to today)
  - `reason`: Optional cancellation reason

  ## Returns
  - `{:ok, booking, refund_amount, refund_transaction_or_pending_refund}` if successful
  - `{:error, reason}` if cancellation fails

  ## Examples
      iex> cancel_booking(booking, ~D[2025-11-10], "User requested cancellation")
      {:ok, %Booking{}, %Money{}, %LedgerTransaction{}}
  """
  def cancel_booking(booking, cancellation_date \\ Date.utc_today(), reason \\ nil) do
    alias Ysc.Ledgers
    alias Ysc.Bookings.{BookingLocker, PendingRefund}

    # First, always cancel the booking and free up inventory
    cancel_result =
      case booking.status do
        :hold ->
          BookingLocker.release_hold(booking.id)

        :complete ->
          BookingLocker.cancel_complete_booking(booking.id)

        _ ->
          # Booking already canceled or in invalid state
          {:error, :invalid_status}
      end

    case cancel_result do
      {:ok, canceled_booking} ->
        # Get the original payment for this booking first
        case get_booking_payment(canceled_booking) do
          {:ok, payment} ->
            # Calculate refund amount
            case calculate_refund(canceled_booking, cancellation_date) do
              {:ok, refund_amount, applied_rule} ->
                # If refund_amount is nil, it means full refund (no policy)
                # In that case, use the full payment amount
                actual_refund_amount =
                  if is_nil(refund_amount) do
                    payment.amount
                  else
                    refund_amount
                  end

                # Process refund if amount > 0
                if actual_refund_amount && Money.positive?(actual_refund_amount) do
                  # Check if refund is 100% (full refund)
                  is_full_refund = Money.equal?(actual_refund_amount, payment.amount)

                  if is_full_refund do
                    # Full refund - create refund in Stripe
                    refund_reason =
                      if applied_rule do
                        "Booking cancellation: #{reason || "No reason provided"}. Applied policy rule: #{applied_rule.days_before_checkin} days before check-in, #{applied_rule.refund_percentage}% refund."
                      else
                        "Booking cancellation: #{reason || "No reason provided"}. Full refund (no policy applied)."
                      end

                    # Get the payment intent ID from the payment
                    payment_intent_id = payment.external_payment_id

                    if payment_intent_id && payment.external_provider == :stripe do
                      # Convert refund amount to cents for Stripe
                      refund_amount_cents = money_to_cents(actual_refund_amount)

                      # Create refund in Stripe
                      case create_stripe_refund(
                             payment_intent_id,
                             refund_amount_cents,
                             refund_reason
                           ) do
                        {:ok, stripe_refund} ->
                          # Refund created in Stripe - ledger will be updated via webhook
                          # Return the refund ID so we can track it
                          {:ok, canceled_booking, actual_refund_amount, stripe_refund.id}

                        {:error, reason} ->
                          {:error, {:refund_failed, reason}}
                      end
                    else
                      {:error,
                       {:refund_failed, "Payment does not have a valid Stripe payment intent ID"}}
                    end
                  else
                    # Partial refund - create pending refund for admin review
                    applied_rule_days =
                      if applied_rule, do: applied_rule.days_before_checkin, else: nil

                    applied_rule_percentage =
                      if applied_rule, do: applied_rule.refund_percentage, else: nil

                    pending_refund_attrs = %{
                      booking_id: canceled_booking.id,
                      payment_id: payment.id,
                      policy_refund_amount: actual_refund_amount,
                      status: :pending,
                      cancellation_reason: reason,
                      applied_rule_days_before_checkin: applied_rule_days,
                      applied_rule_refund_percentage: applied_rule_percentage
                    }

                    case %PendingRefund{}
                         |> PendingRefund.changeset(pending_refund_attrs)
                         |> Repo.insert() do
                      {:ok, pending_refund} ->
                        {:ok, canceled_booking, actual_refund_amount, pending_refund}

                      {:error, changeset} ->
                        {:error, {:pending_refund_failed, changeset}}
                    end
                  end
                else
                  # No refund (0% or nil)
                  {:ok, canceled_booking, Money.new(0, :USD), nil}
                end

              {:error, reason} ->
                {:error, {:calculation_failed, reason}}
            end

          {:error, reason} ->
            {:error, {:payment_not_found, reason}}
        end

      {:error, reason} ->
        {:error, {:cancellation_failed, reason}}
    end
  end

  @doc """
  Gets the payment for a booking by looking up ledger entries.

  Returns `{:ok, payment}` if found, or `{:error, :payment_not_found}` if not found.
  """
  def get_booking_payment(booking) do
    import Ecto.Query

    # Find the payment via ledger entries
    # Note: We filter by amount > 0 in Elixir since Money comparison in queries is complex
    entries =
      from(e in Ysc.Ledgers.LedgerEntry,
        where: e.related_entity_type == ^:booking,
        where: e.related_entity_id == ^booking.id,
        preload: [:payment],
        order_by: [desc: e.inserted_at]
      )
      |> Repo.all()

    # Filter for positive amounts and get the first one
    entry =
      entries
      |> Enum.find(fn e ->
        e.amount && Money.positive?(e.amount)
      end)

    if entry && entry.payment do
      {:ok, entry.payment}
    else
      {:error, :payment_not_found}
    end
  end

  @doc """
  Gets daily availability information for Clear Lake property.

  Returns a map where keys are dates (as Date structs) and values are maps with:
  - `day_bookings_count`: Number of guests already booked for day bookings
  - `spots_available`: Number of spots remaining (12 - day_bookings_count)
  - `has_buyout`: Whether there's a buyout booking on this date
  - `is_blacked_out`: Whether the date is in a blackout period
  - `can_book_day`: Whether day bookings are possible (not blacked out and spots available)
  - `can_book_buyout`: Whether buyout is possible (not blacked out and no day bookings)

  ## Parameters
  - `start_date`: Start date of the range to check
  - `end_date`: End date of the range to check

  ## Returns
  A map of dates to availability information.
  """
  def get_clear_lake_daily_availability(start_date, end_date) do
    date_range = Date.range(start_date, end_date) |> Enum.to_list()

    # Get all bookings that overlap with the date range
    # Only preload what we need - we don't need user data for availability calculation
    # Filter out canceled and hold bookings - only count complete bookings for availability
    all_bookings = list_bookings(:clear_lake, start_date, end_date, preload: [:rooms])

    bookings =
      Enum.filter(all_bookings, fn booking ->
        booking.status == :complete
      end)

    # Get all blackouts that overlap with the date range
    blackouts = get_overlapping_blackouts(:clear_lake, start_date, end_date)

    # Create a set of blacked out dates
    blacked_out_dates =
      blackouts
      |> Enum.flat_map(fn blackout ->
        Date.range(blackout.start_date, blackout.end_date) |> Enum.to_list()
      end)
      |> MapSet.new()

    # Initialize availability map
    availability =
      date_range
      |> Enum.map(fn date -> {date, %{day_bookings_count: 0, has_buyout: false}} end)
      |> Map.new()

    # Process bookings to count guests per day and check for buyouts
    availability =
      bookings
      |> Enum.reduce(availability, fn booking, acc ->
        booking_date_range =
          Date.range(booking.checkin_date, booking.checkout_date) |> Enum.to_list()

        booking_date_range
        |> Enum.reduce(acc, fn date, date_acc ->
          if Map.has_key?(date_acc, date) do
            case booking.booking_mode do
              :day ->
                current_count = date_acc[date].day_bookings_count

                Map.put(date_acc, date, %{
                  date_acc[date]
                  | day_bookings_count: current_count + booking.guests_count
                })

              :buyout ->
                Map.put(date_acc, date, %{date_acc[date] | has_buyout: true})

              _ ->
                date_acc
            end
          else
            date_acc
          end
        end)
      end)

    # Get capacity_held from PropertyInventory for each date to account for hold bookings
    held_capacity_by_date =
      from(pi in PropertyInventory,
        where: pi.property == :clear_lake,
        where: pi.day >= ^start_date and pi.day <= ^end_date,
        select: {pi.day, pi.capacity_held}
      )
      |> Repo.all()
      |> Map.new()

    # Finalize availability information for each date
    availability
    |> Enum.map(fn {date, info} ->
      is_blacked_out = MapSet.member?(blacked_out_dates, date)
      # Account for both confirmed bookings and held capacity
      capacity_held = Map.get(held_capacity_by_date, date, 0)
      total_occupied = info.day_bookings_count + capacity_held
      spots_available = max(0, 12 - total_occupied)
      can_book_day = not is_blacked_out and spots_available > 0 and not info.has_buyout

      can_book_buyout =
        not is_blacked_out and not info.has_buyout and total_occupied == 0

      {
        date,
        %{
          day_bookings_count: info.day_bookings_count,
          spots_available: spots_available,
          has_buyout: info.has_buyout,
          is_blacked_out: is_blacked_out,
          can_book_day: can_book_day,
          can_book_buyout: can_book_buyout
        }
      }
    end)
    |> Map.new()
  end

  @doc """
  Lists all pending refunds that require admin review.
  """
  def list_pending_refunds do
    import Ecto.Query

    from(pr in PendingRefund,
      where: pr.status == :pending,
      order_by: [asc: pr.inserted_at],
      preload: [:booking, :payment]
    )
    |> Repo.all()
  end

  @doc """
  Gets a pending refund by ID with all associations preloaded.
  """
  def get_pending_refund!(id) do
    import Ecto.Query

    from(pr in PendingRefund,
      where: pr.id == ^id,
      preload: [:booking, :payment, :reviewed_by]
    )
    |> Repo.one!()
  end

  @doc """
  Approves and processes a pending refund.

  The admin can specify a different refund amount than the policy amount.
  If no admin_refund_amount is provided, the policy_refund_amount is used.

  ## Parameters
  - `pending_refund`: The pending refund to approve
  - `admin_refund_amount`: Optional custom refund amount (defaults to policy amount)
  - `admin_notes`: Optional notes from the admin
  - `reviewed_by`: The admin user approving the refund

  ## Returns
  - `{:ok, pending_refund, refund_transaction}` if successful
  - `{:error, reason}` if processing fails
  """
  def approve_pending_refund(
        pending_refund,
        admin_refund_amount \\ nil,
        admin_notes \\ nil,
        reviewed_by
      ) do
    alias Ysc.MoneyHelper

    # Use admin amount if provided, otherwise use policy amount
    refund_amount = admin_refund_amount || pending_refund.policy_refund_amount

    refund_reason =
      if admin_notes do
        "Booking cancellation refund (admin approved): #{admin_notes}. Policy amount: #{MoneyHelper.format_money!(pending_refund.policy_refund_amount)}, Refunded amount: #{MoneyHelper.format_money!(refund_amount)}."
      else
        "Booking cancellation refund (admin approved). Policy amount: #{MoneyHelper.format_money!(pending_refund.policy_refund_amount)}, Refunded amount: #{MoneyHelper.format_money!(refund_amount)}."
      end

    # Get the payment to find the payment intent ID
    payment = Repo.get!(Ysc.Ledgers.Payment, pending_refund.payment_id)

    if payment.external_payment_id && payment.external_provider == :stripe do
      # Convert refund amount to cents for Stripe
      refund_amount_cents = money_to_cents(refund_amount)

      # Create refund in Stripe
      case create_stripe_refund(payment.external_payment_id, refund_amount_cents, refund_reason) do
        {:ok, stripe_refund} ->
          # Update pending refund status - ledger will be updated via webhook
          updated_pending_refund =
            pending_refund
            |> PendingRefund.changeset(%{
              status: :approved,
              admin_refund_amount: refund_amount,
              admin_notes: admin_notes,
              reviewed_by_id: reviewed_by.id,
              reviewed_at: DateTime.utc_now()
            })
            |> Repo.update!()

          {:ok, updated_pending_refund, stripe_refund.id}

        {:error, reason} ->
          {:error, {:refund_failed, reason}}
      end
    else
      {:error, {:refund_failed, "Payment does not have a valid Stripe payment intent ID"}}
    end
  end

  @doc """
  Rejects a pending refund.

  ## Parameters
  - `pending_refund`: The pending refund to reject
  - `admin_notes`: Optional notes explaining why the refund was rejected
  - `reviewed_by`: The admin user rejecting the refund

  ## Returns
  - `{:ok, pending_refund}` if successful
  - `{:error, reason}` if update fails
  """
  def reject_pending_refund(pending_refund, admin_notes \\ nil, reviewed_by) do
    pending_refund
    |> PendingRefund.changeset(%{
      status: :rejected,
      admin_notes: admin_notes,
      reviewed_by_id: reviewed_by.id,
      reviewed_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  ## Private Functions

  # Helper function to safely convert Money to cents
  defp money_to_cents(%Money{amount: amount, currency: :USD}) do
    # Use Decimal for precise conversion to avoid floating-point errors
    amount
    |> Decimal.mult(100)
    |> Decimal.to_integer()
  end

  defp money_to_cents(%Money{amount: amount, currency: _currency}) do
    # For other currencies, use same conversion
    amount
    |> Decimal.mult(100)
    |> Decimal.to_integer()
  end

  defp money_to_cents(_) do
    # Fallback for invalid money values
    0
  end

  @doc """
  Creates a refund in Stripe for a payment intent.

  ## Parameters
  - `payment_intent_id`: The Stripe payment intent ID
  - `amount_cents`: The refund amount in cents
  - `reason`: Reason for the refund

  ## Returns
  - `{:ok, %Stripe.Refund{}}` on success
  - `{:error, reason}` on failure
  """
  defp create_stripe_refund(payment_intent_id, amount_cents, reason) do
    require Logger

    # First, retrieve the payment intent to get the charge ID
    case Stripe.PaymentIntent.retrieve(payment_intent_id, %{expand: ["charges"]}) do
      {:ok, payment_intent} ->
        # Get the charge ID from the payment intent
        charge_id =
          case payment_intent.charges do
            %Stripe.List{data: [%Stripe.Charge{id: charge_id} | _]} -> charge_id
            [%Stripe.Charge{id: charge_id} | _] -> charge_id
            _ -> nil
          end

        if charge_id do
          # Create refund using the charge ID
          refund_params = %{
            charge: charge_id,
            amount: amount_cents,
            reason: "requested_by_customer",
            metadata: %{
              reason: reason,
              payment_intent_id: payment_intent_id
            }
          }

          case Stripe.Refund.create(refund_params) do
            {:ok, refund} ->
              Logger.info("Stripe refund created successfully",
                refund_id: refund.id,
                payment_intent_id: payment_intent_id,
                amount_cents: amount_cents
              )

              {:ok, refund}

            {:error, %Stripe.Error{} = error} ->
              Logger.error("Stripe refund creation failed",
                payment_intent_id: payment_intent_id,
                error: error.message
              )

              {:error, error.message}

            {:error, reason} ->
              Logger.error("Stripe refund creation failed",
                payment_intent_id: payment_intent_id,
                error: inspect(reason)
              )

              {:error, "Failed to create refund in Stripe"}
          end
        else
          Logger.error("No charge found in payment intent",
            payment_intent_id: payment_intent_id
          )

          {:error, "No charge found for payment intent"}
        end

      {:error, %Stripe.Error{} = error} ->
        Logger.error("Failed to retrieve payment intent for refund",
          payment_intent_id: payment_intent_id,
          error: error.message
        )

        {:error, "Failed to retrieve payment intent: #{error.message}"}

      {:error, reason} ->
        Logger.error("Failed to retrieve payment intent for refund",
          payment_intent_id: payment_intent_id,
          error: inspect(reason)
        )

        {:error, "Failed to retrieve payment intent"}
    end
  end
end
