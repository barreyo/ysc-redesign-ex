defmodule Ysc.Bookings.SeasonHelpers do
  @moduledoc """
  Shared helper functions for season-based booking logic.

  Provides utilities for:
  - Getting current season date ranges
  - Calculating max booking dates (restricted to current season)
  - Validating dates are within the current season
  """

  alias Ysc.Bookings.Season

  @doc """
  Gets the current season and its actual date range for a property.

  Returns `{current_season, season_start_date, season_end_date}`.
  """
  def get_current_season_info(property, today \\ Date.utc_today()) do
    current_season = Season.for_date(property, today)

    if current_season do
      {season_start_date, season_end_date} = get_season_date_range(current_season, today)
      {current_season, season_start_date, season_end_date}
    else
      {nil, nil, nil}
    end
  end

  @doc """
  Gets the actual date range for a season based on a reference date.

  Handles year-spanning seasons (e.g., Nov 1 - Apr 30).
  Returns `{start_date, end_date}`.
  """
  def get_season_date_range(season, reference_date) do
    start_date = get_season_start_date(season, reference_date)
    end_date = get_season_end_date(season, reference_date)
    {start_date, end_date}
  end

  @doc """
  Calculates the maximum booking date based on the current season.

  Bookings are only allowed within the current season. If the season has
  an advance booking limit, it's applied within the season boundaries.
  """
  def calculate_max_booking_date(property, today \\ Date.utc_today()) do
    {current_season, _season_start, season_end} = get_current_season_info(property, today)

    if current_season do
      # If season has advance booking limit, apply it within the season
      if current_season.advance_booking_days && current_season.advance_booking_days > 0 do
        max_by_advance_limit = Date.add(today, current_season.advance_booking_days)
        # Return the earlier of: season end date or advance booking limit
        if Date.compare(max_by_advance_limit, season_end) == :lt do
          max_by_advance_limit
        else
          season_end
        end
      else
        # No advance booking limit - can book up to season end
        season_end
      end
    else
      # No current season found - use a conservative default (shouldn't happen in practice)
      Date.add(today, 30)
    end
  end

  @doc """
  Validates that check-in and check-out dates are within the current season.

  Returns a map of errors (empty if valid).
  """
  def validate_season_date_range(property, checkin_date, checkout_date, today \\ Date.utc_today()) do
    {current_season, season_start, season_end} = get_current_season_info(property, today)

    if current_season && season_start && season_end do
      cond do
        Date.compare(checkin_date, season_start) == :lt ->
          %{
            season_date_range:
              "Bookings are only available during the current #{current_season.name} season (#{format_date(season_start)} - #{format_date(season_end)}). Check-in date must be on or after #{format_date(season_start)}."
          }

        Date.compare(checkin_date, season_end) == :gt ->
          %{
            season_date_range:
              "Bookings are only available during the current #{current_season.name} season (#{format_date(season_start)} - #{format_date(season_end)}). Check-in date must be on or before #{format_date(season_end)}."
          }

        Date.compare(checkout_date, season_end) == :gt ->
          %{
            season_date_range:
              "Bookings are only available during the current #{current_season.name} season (#{format_date(season_start)} - #{format_date(season_end)}). Check-out date must be on or before #{format_date(season_end)}."
          }

        true ->
          %{}
      end
    else
      %{}
    end
  end

  @doc """
  Validates advance booking limit using the current season's rules.
  """
  def validate_advance_booking_limit(
        property,
        checkin_date,
        checkout_date,
        today \\ Date.utc_today()
      ) do
    current_season = Season.for_date(property, today)

    # Only enforce limit if season exists and has advance_booking_days set
    if current_season && current_season.advance_booking_days &&
         current_season.advance_booking_days > 0 do
      max_booking_date = Date.add(today, current_season.advance_booking_days)

      cond do
        Date.compare(checkin_date, max_booking_date) == :gt ->
          %{
            advance_booking_limit:
              "Bookings can only be made up to #{current_season.advance_booking_days} days in advance. Maximum check-in date is #{format_date(max_booking_date)}"
          }

        Date.compare(checkout_date, max_booking_date) == :gt ->
          %{
            advance_booking_limit:
              "Bookings can only be made up to #{current_season.advance_booking_days} days in advance. Maximum check-out date is #{format_date(max_booking_date)}"
          }

        true ->
          %{}
      end
    else
      %{}
    end
  end

  # Get the start date of the current season occurrence
  defp get_season_start_date(season, today) do
    {today_month, today_day} = {today.month, today.day}
    {start_month, start_day} = {season.start_date.month, season.start_date.day}
    {end_month, end_day} = {season.end_date.month, season.end_date.day}

    # If season spans years (e.g., Nov to Apr)
    if start_month > end_month do
      # Check if we're before the end date in the current year
      if {today_month, today_day} <= {end_month, end_day} do
        # We're in the later part of the season (Jan-Apr), start was last year
        Date.new!(today.year - 1, start_month, start_day)
      else
        # We're in the earlier part (Nov-Dec), start is this year
        Date.new!(today.year, start_month, start_day)
      end
    else
      # Same-year range - start is this year
      Date.new!(today.year, start_month, start_day)
    end
  end

  # Get the end date of the current season occurrence
  defp get_season_end_date(season, today) do
    {today_month, today_day} = {today.month, today.day}
    {start_month, start_day} = {season.start_date.month, season.start_date.day}
    {end_month, end_day} = {season.end_date.month, season.end_date.day}

    # If season spans years (e.g., Nov to Apr)
    if start_month > end_month do
      # Check if we're before the end date in the current year
      if {today_month, today_day} <= {end_month, end_day} do
        # We're in the later part of the season (Jan-Apr), end is this year
        Date.new!(today.year, end_month, end_day)
      else
        # We're in the earlier part (Nov-Dec), end is next year
        Date.new!(today.year + 1, end_month, end_day)
      end
    else
      # Same-year range - end is this year
      Date.new!(today.year, end_month, end_day)
    end
  end

  defp format_date(date) do
    Calendar.strftime(date, "%B %d, %Y")
  end
end
