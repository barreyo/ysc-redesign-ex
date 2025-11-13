defmodule Ysc.Bookings.BookingValidator do
  @moduledoc """
  Validates bookings according to property-specific rules.

  ## Tahoe Rules:
  - Winter: Only individual rooms
  - Summer: Individual rooms OR full buyout
  - If booking contains Saturday, must also reserve Sunday (full weekend)
  - Only one active booking per user at a time (all seasons)
  - Maximum 4 nights per booking
  - Family membership: Up to 2 rooms in same time period (same or overlapping dates)
  - Single membership: Only 1 room per booking

  ## Clear Lake Rules:
  - Book by number of guests (not rooms)
  - Priced per guest per day
  - Maximum 12 guests per day
  - Option for "full buyout"
  """
  import Ecto.Query, warn: false
  alias Ysc.Repo
  alias Ysc.Bookings.{Booking, Season, Room}
  alias Ysc.Accounts.User
  alias Ysc.Subscriptions

  @max_nights_tahoe 4
  @max_guests_clear_lake 12

  @doc """
  Validates a booking changeset according to all business rules.

  ## Options
  - `:skip_validation` - If true, skips all business rule validations (useful for admin-created bookings)
  """
  def validate(changeset, opts \\ []) do
    # Skip all validation if requested (for admin-created bookings)
    if opts[:skip_validation] do
      changeset
    else
      user = opts[:user] || get_user_from_changeset(changeset)
      property = Ecto.Changeset.get_field(changeset, :property)

      changeset
      |> validate_booking_mode(property)
      |> validate_advance_booking_limit(property)
      |> validate_weekend_requirement()
      |> validate_max_nights()
      |> validate_single_active_booking(user, property)
      |> validate_membership_room_limits(user, property)
      |> validate_clear_lake_guest_limits(property)
      |> validate_room_capacity()
    end
  end

  # Tahoe: During winter, only individual rooms; during summer, rooms or buyout
  defp validate_booking_mode(changeset, :tahoe) do
    checkin_date = Ecto.Changeset.get_field(changeset, :checkin_date)
    booking_mode = Ecto.Changeset.get_field(changeset, :booking_mode)
    rooms = Ecto.Changeset.get_field(changeset, :rooms) || []
    has_rooms = is_list(rooms) && length(rooms) > 0

    if checkin_date do
      season = Season.for_date(:tahoe, checkin_date)

      cond do
        is_nil(season) ->
          changeset

        season.name == "Winter" ->
          # Winter: only rooms allowed (no buyouts)
          if !has_rooms or booking_mode == :buyout do
            Ecto.Changeset.add_error(
              changeset,
              :booking_mode,
              "Winter season only allows individual room bookings, not buyouts"
            )
          else
            changeset
          end

        season.name == "Summer" ->
          # Summer: rooms or buyout allowed - validation passes if either rooms are set or booking_mode is buyout
          changeset

        true ->
          changeset
      end
    else
      changeset
    end
  end

  defp validate_booking_mode(changeset, _property), do: changeset

  # Validate advance booking limit based on season's configurable days
  # Uses cross-season logic: checks the season for checkin_date and next season's limits
  defp validate_advance_booking_limit(changeset, property)
       when property in [:tahoe, :clear_lake] do
    checkin_date = Ecto.Changeset.get_field(changeset, :checkin_date)
    checkout_date = Ecto.Changeset.get_field(changeset, :checkout_date)

    if checkin_date && checkout_date do
      alias Ysc.Bookings.SeasonHelpers

      validation_errors =
        SeasonHelpers.validate_advance_booking_limit(property, checkin_date, checkout_date)

      if Map.has_key?(validation_errors, :advance_booking_limit) do
        Ecto.Changeset.add_error(
          changeset,
          :checkin_date,
          validation_errors.advance_booking_limit
        )
      else
        changeset
      end
    else
      changeset
    end
  end

  defp validate_advance_booking_limit(changeset, _property), do: changeset

  # If booking contains Saturday, must also reserve Sunday
  defp validate_weekend_requirement(changeset) do
    checkin_date = Ecto.Changeset.get_field(changeset, :checkin_date)
    checkout_date = Ecto.Changeset.get_field(changeset, :checkout_date)
    property = Ecto.Changeset.get_field(changeset, :property)

    if checkin_date && checkout_date && property == :tahoe do
      date_range = Date.range(checkin_date, checkout_date) |> Enum.to_list()

      has_saturday =
        Enum.any?(date_range, fn date ->
          day_of_week(date) == 6
        end)

      if has_saturday do
        # Check if Sunday is included
        has_sunday =
          Enum.any?(date_range, fn date ->
            day_of_week(date) == 7
          end)

        if not has_sunday do
          Ecto.Changeset.add_error(
            changeset,
            :checkout_date,
            "Bookings containing Saturday must also include Sunday (full weekend required)"
          )
        else
          changeset
        end
      else
        changeset
      end
    else
      changeset
    end
  end

  # Maximum nights validation based on season configuration
  defp validate_max_nights(changeset) do
    checkin_date = Ecto.Changeset.get_field(changeset, :checkin_date)
    checkout_date = Ecto.Changeset.get_field(changeset, :checkout_date)
    property = Ecto.Changeset.get_field(changeset, :property)

    if checkin_date && checkout_date && property do
      nights = Date.diff(checkout_date, checkin_date)

      # Get max nights from season for check-in date
      max_nights =
        if checkin_date do
          season = Season.for_date(property, checkin_date)
          Season.get_max_nights(season, property)
        else
          # Fallback to property defaults
          case property do
            :tahoe -> 4
            :clear_lake -> 30
            _ -> 4
          end
        end

      if nights > max_nights do
        Ecto.Changeset.add_error(
          changeset,
          :checkout_date,
          "Maximum #{max_nights} nights allowed per booking"
        )
      else
        changeset
      end
    else
      changeset
    end
  end

  # Only one active booking per user at a time (all seasons)
  defp validate_single_active_booking(changeset, user, :tahoe) do
    checkin_date = Ecto.Changeset.get_field(changeset, :checkin_date)
    checkout_date = Ecto.Changeset.get_field(changeset, :checkout_date)
    booking_id = Ecto.Changeset.get_field(changeset, :id)
    user_id = Ecto.Changeset.get_field(changeset, :user_id) || (user && user.id)

    if checkin_date && checkout_date && user_id do
      # Check for overlapping active bookings for this user
      overlapping_query =
        from b in Booking,
          where: b.user_id == ^user_id,
          where: b.property == :tahoe,
          where:
            fragment(
              "? < ? AND ? > ?",
              b.checkin_date,
              ^checkout_date,
              b.checkout_date,
              ^checkin_date
            )

      overlapping_query =
        if booking_id do
          from b in overlapping_query, where: b.id != ^booking_id
        else
          overlapping_query
        end

      overlapping_count = Repo.aggregate(overlapping_query, :count, :id)

      if overlapping_count > 0 do
        Ecto.Changeset.add_error(
          changeset,
          :checkin_date,
          "You can only have one active booking at a time. Please complete your existing booking first."
        )
      else
        changeset
      end
    else
      changeset
    end
  end

  defp validate_single_active_booking(changeset, _user, _property), do: changeset

  # Membership-based room limits: Family = 2 rooms, Single = 1 room
  # Family memberships can book 2 rooms with overlapping dates (same timeframe)
  defp validate_membership_room_limits(changeset, user, :tahoe) do
    checkin_date = Ecto.Changeset.get_field(changeset, :checkin_date)
    checkout_date = Ecto.Changeset.get_field(changeset, :checkout_date)
    user_id = Ecto.Changeset.get_field(changeset, :user_id) || (user && user.id)
    booking_id = Ecto.Changeset.get_field(changeset, :id)

    if checkin_date && checkout_date && user_id && not is_nil(user) do
      membership_type = get_membership_type(user)

      max_rooms =
        case membership_type do
          :family -> 2
          :lifetime -> 2
          _ -> 1
        end

      # For family memberships, check for overlapping dates (same timeframe)
      # For single memberships, check for exact same dates
      # Check for bookings that have rooms (via join table)
      overlapping_bookings_query =
        if membership_type in [:family, :lifetime] do
          # Family: Allow overlapping dates (same timeframe)
          from b in Booking,
            join: br in "booking_rooms",
            on: br.booking_id == b.id,
            where: b.user_id == ^user_id,
            where: b.property == :tahoe,
            where:
              fragment(
                "? < ? AND ? > ?",
                b.checkin_date,
                ^checkout_date,
                b.checkout_date,
                ^checkin_date
              )
        else
          # Single: Only exact same dates
          from b in Booking,
            join: br in "booking_rooms",
            on: br.booking_id == b.id,
            where: b.user_id == ^user_id,
            where: b.property == :tahoe,
            where: b.checkin_date == ^checkin_date,
            where: b.checkout_date == ^checkout_date
        end

      overlapping_bookings_query =
        if booking_id do
          from b in overlapping_bookings_query, where: b.id != ^booking_id
        else
          overlapping_bookings_query
        end

      existing_room_count = Repo.aggregate(overlapping_bookings_query, :count, :id)

      if existing_room_count >= max_rooms do
        Ecto.Changeset.add_error(
          changeset,
          :room_id,
          "#{String.capitalize("#{membership_type}")} membership allows maximum #{max_rooms} room(s) in the same time period"
        )
      else
        changeset
      end
    else
      changeset
    end
  end

  defp validate_membership_room_limits(changeset, _user, _property), do: changeset

  # Clear Lake: Maximum 12 guests per day
  defp validate_clear_lake_guest_limits(changeset, :clear_lake) do
    guests_count = Ecto.Changeset.get_field(changeset, :guests_count)
    checkin_date = Ecto.Changeset.get_field(changeset, :checkin_date)
    checkout_date = Ecto.Changeset.get_field(changeset, :checkout_date)
    booking_mode = Ecto.Changeset.get_field(changeset, :booking_mode)

    if guests_count && checkin_date && checkout_date && booking_mode != :buyout do
      if guests_count > @max_guests_clear_lake do
        Ecto.Changeset.add_error(
          changeset,
          :guests_count,
          "Maximum #{@max_guests_clear_lake} guests allowed per day for Clear Lake"
        )
      else
        # Check daily guest limits across all bookings
        date_range = Date.range(checkin_date, checkout_date) |> Enum.to_list()
        booking_id = Ecto.Changeset.get_field(changeset, :id)

        date_range
        |> Enum.reduce(changeset, fn date, acc ->
          # Count existing guests for this date (excluding current booking if updating)
          existing_guests_query =
            from b in Booking,
              where: b.property == :clear_lake,
              where: b.checkin_date <= ^date,
              where: b.checkout_date >= ^date,
              where: b.booking_mode != :buyout,
              select: fragment("COALESCE(SUM(?), 0)", b.guests_count)

          existing_guests_query =
            if booking_id do
              from b in existing_guests_query, where: b.id != ^booking_id
            else
              existing_guests_query
            end

          existing_guests = Repo.one(existing_guests_query) || 0
          total_guests = existing_guests + guests_count

          if total_guests > @max_guests_clear_lake do
            Ecto.Changeset.add_error(
              acc,
              :guests_count,
              "Maximum #{@max_guests_clear_lake} guests per day exceeded. #{existing_guests} guests already booked on #{date}."
            )
          else
            acc
          end
        end)
      end
    else
      changeset
    end
  end

  defp validate_clear_lake_guest_limits(changeset, _property), do: changeset

  # Validate room capacity (guests_count <= sum of room capacities for all rooms)
  defp validate_room_capacity(changeset) do
    rooms = Ecto.Changeset.get_field(changeset, :rooms) || []
    guests_count = Ecto.Changeset.get_field(changeset, :guests_count)

    if length(rooms) > 0 && guests_count do
      # For multiple rooms, sum the capacities
      total_capacity =
        Enum.reduce(rooms, 0, fn room, acc ->
          room_capacity = if is_struct(room), do: room.capacity_max, else: 0
          acc + room_capacity
        end)

      if total_capacity > 0 && guests_count > total_capacity do
        room_names =
          Enum.map_join(rooms, ", ", fn room ->
            if is_struct(room), do: room.name, else: "Unknown"
          end)

        Ecto.Changeset.add_error(
          changeset,
          :guests_count,
          "Total room capacity is #{total_capacity} guests, but #{guests_count} guests requested (#{room_names})"
        )
      else
        changeset
      end
    else
      changeset
    end
  end

  # Helper functions

  defp get_user_from_changeset(changeset) do
    user_id = Ecto.Changeset.get_field(changeset, :user_id)

    if user_id do
      Repo.get(User, user_id) |> Repo.preload(:subscriptions)
    else
      nil
    end
  end

  defp get_membership_type(user) do
    # Check for lifetime membership first
    if Ysc.Accounts.has_lifetime_membership?(user) do
      :lifetime
    else
      # Get active subscriptions
      subscriptions =
        case user.subscriptions do
          %Ecto.Association.NotLoaded{} ->
            Ysc.Subscriptions.list_subscriptions(user)

          subscriptions when is_list(subscriptions) ->
            subscriptions

          _ ->
            []
        end

      active_subscriptions =
        Enum.filter(subscriptions, fn sub ->
          Subscriptions.valid?(sub)
        end)

      case active_subscriptions do
        [] ->
          :none

        [subscription | _] ->
          get_membership_type_from_subscription(subscription)

        multiple ->
          most_expensive = get_most_expensive_subscription(multiple)
          get_membership_type_from_subscription(most_expensive)
      end
    end
  end

  defp get_membership_type_from_subscription(subscription) do
    subscription = Repo.preload(subscription, :subscription_items)

    case subscription.subscription_items do
      [item | _] ->
        membership_plans = Application.get_env(:ysc, :membership_plans, [])

        case Enum.find(membership_plans, &(&1.stripe_price_id == item.stripe_price_id)) do
          %{id: id} -> id
          _ -> :none
        end

      _ ->
        :none
    end
  end

  defp get_most_expensive_subscription(subscriptions) do
    membership_plans = Application.get_env(:ysc, :membership_plans, [])

    price_to_amount =
      Map.new(membership_plans, fn plan ->
        {plan.stripe_price_id, plan.amount}
      end)

    Enum.max_by(subscriptions, fn subscription ->
      subscription = Repo.preload(subscription, :subscription_items)

      case subscription.subscription_items do
        [item | _] -> Map.get(price_to_amount, item.stripe_price_id, 0)
        _ -> 0
      end
    end)
  end

  defp day_of_week(date) do
    # Returns 1-7 where 1 = Monday, 6 = Saturday, 7 = Sunday
    Date.day_of_week(date, :monday)
  end
end
