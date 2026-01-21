defmodule Ysc.Bookings.HoldExpiryWorkerTest do
  @moduledoc """
  Tests for HoldExpiryWorker module.

  These tests verify:
  - Expiration of expired booking holds
  - Error handling for hold release failures
  - Worker job execution
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Bookings.{Booking, HoldExpiryWorker}
  alias Ysc.Repo

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    user = user_fixture()

    # Ensure user is active
    user =
      user
      |> Ecto.Changeset.change(state: :active)
      |> Repo.update!()

    %{user: user}
  end

  describe "expire_expired_holds/0" do
    test "expires bookings with expired holds", %{user: user} do
      # Create a booking with an expired hold by inserting directly
      checkin_date = Date.add(Date.utc_today(), 7)
      checkout_date = Date.add(checkin_date, 2)

      booking =
        %Booking{}
        |> Booking.changeset(
          %{
            user_id: user.id,
            property: :tahoe,
            booking_mode: :room,
            checkin_date: checkin_date,
            checkout_date: checkout_date,
            guests_count: 2,
            status: :hold,
            hold_expires_at:
              DateTime.add(DateTime.utc_now() |> DateTime.truncate(:second), -1, :hour),
            total_price: Money.new(100, :USD)
          },
          skip_validation: true
        )
        |> Repo.insert!()

      # Verify booking is in hold status
      booking = Repo.get!(Booking, booking.id)
      assert booking.status == :hold
      assert booking.hold_expires_at != nil

      # Run the expiration worker
      HoldExpiryWorker.expire_expired_holds()

      # Verify booking is now canceled
      booking = Repo.get!(Booking, booking.id)
      assert booking.status == :canceled
    end

    test "does not expire bookings with future hold expiration", %{user: user} do
      checkin_date = Date.add(Date.utc_today(), 7)
      checkout_date = Date.add(checkin_date, 2)

      booking =
        %Booking{}
        |> Booking.changeset(
          %{
            user_id: user.id,
            property: :tahoe,
            booking_mode: :room,
            checkin_date: checkin_date,
            checkout_date: checkout_date,
            guests_count: 2,
            status: :hold,
            hold_expires_at:
              DateTime.add(DateTime.utc_now() |> DateTime.truncate(:second), 1, :hour),
            total_price: Money.new(100, :USD)
          },
          skip_validation: true
        )
        |> Repo.insert!()

      # Run the expiration worker
      HoldExpiryWorker.expire_expired_holds()

      # Verify booking is still in hold status
      booking = Repo.get!(Booking, booking.id)
      assert booking.status == :hold
    end

    test "does not expire bookings that are not in hold status", %{user: user} do
      checkin_date = Date.add(Date.utc_today(), 7)
      checkout_date = Date.add(checkin_date, 2)

      booking =
        %Booking{}
        |> Booking.changeset(
          %{
            user_id: user.id,
            property: :tahoe,
            booking_mode: :room,
            checkin_date: checkin_date,
            checkout_date: checkout_date,
            guests_count: 2,
            status: :draft,
            hold_expires_at:
              DateTime.add(DateTime.utc_now() |> DateTime.truncate(:second), -1, :hour),
            total_price: Money.new(100, :USD)
          },
          skip_validation: true
        )
        |> Repo.insert!()

      # Run the expiration worker
      HoldExpiryWorker.expire_expired_holds()

      # Verify booking status is unchanged
      booking = Repo.get!(Booking, booking.id)
      assert booking.status == :draft
    end

    test "handles multiple expired holds", %{user: user} do
      checkin_date = Date.add(Date.utc_today(), 7)
      checkout_date = Date.add(checkin_date, 2)

      # Create multiple bookings with expired holds
      for i <- 1..3 do
        %Booking{}
        |> Booking.changeset(
          %{
            user_id: user.id,
            property: :tahoe,
            booking_mode: :room,
            checkin_date: Date.add(checkin_date, i),
            checkout_date: Date.add(checkout_date, i),
            guests_count: 2,
            status: :hold,
            hold_expires_at:
              DateTime.add(DateTime.utc_now() |> DateTime.truncate(:second), -i, :hour),
            total_price: Money.new(100, :USD)
          },
          skip_validation: true
        )
        |> Repo.insert!()
      end

      # Verify all are in hold status
      expired_holds =
        Booking
        |> where([b], b.status == :hold and b.hold_expires_at < ^DateTime.utc_now())
        |> Repo.all()

      assert length(expired_holds) == 3

      # Run the expiration worker
      HoldExpiryWorker.expire_expired_holds()

      # Verify all are now canceled
      expired_holds =
        Booking
        |> where([b], b.status == :hold and b.hold_expires_at < ^DateTime.utc_now())
        |> Repo.all()

      assert expired_holds == []

      canceled_bookings =
        Booking
        |> where([b], b.status == :canceled)
        |> Repo.all()

      assert length(canceled_bookings) == 3
    end
  end

  describe "perform/1" do
    test "executes expiration and returns success" do
      result = HoldExpiryWorker.perform(%Oban.Job{})
      assert {:ok, "Expired expired booking holds"} == result
    end
  end
end
