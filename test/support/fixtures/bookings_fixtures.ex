defmodule Ysc.BookingsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ysc.Bookings` context.
  """

  alias Ysc.Bookings

  def booking_fixture(attrs \\ %{}) do
    user_id = attrs[:user_id] || Ysc.AccountsFixtures.user_fixture().id
    checkin = Date.utc_today() |> Date.add(7)

    # Ensure we don't hit the "Saturday must include Sunday" rule
    # Start on a Monday, and stay for 3 nights (checkout Thursday)
    # This satisfies both "Saturday requires Sunday" and "Max 4 nights" rules.
    checkin =
      case Date.day_of_week(checkin) do
        1 -> checkin
        n -> Date.add(checkin, 8 - n)
      end

    checkout = Date.add(checkin, 3)

    {:ok, booking} =
      attrs
      |> Enum.into(%{
        checkin_date: checkin,
        checkout_date: checkout,
        guests_count: 2,
        property: :tahoe,
        booking_mode: :buyout,
        user_id: user_id,
        status: :draft,
        total_price: Money.new(200, :USD)
      })
      |> Bookings.create_booking()

    booking
  end
end
