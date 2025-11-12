defmodule Ysc.Bookings.HoldExpiryWorker do
  @moduledoc """
  Background worker for handling booking hold expiry.

  This worker runs periodically to:
  - Find bookings with status = :hold AND hold_expires_at < now()
  - Lock the same inventory rows, reverse the hold, move to :canceled
  - Release inventory back to available
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query
  require Logger

  alias Ysc.Bookings.{Booking, BookingLocker}

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    expire_expired_holds()
    {:ok, "Expired expired booking holds"}
  end

  @doc """
  Manually trigger expiration of expired holds.
  This can be called from a cron job or scheduled task.
  """
  def expire_expired_holds do
    now = DateTime.utc_now()

    Booking
    |> where([b], b.status == :hold and b.hold_expires_at < ^now)
    |> Ysc.Repo.all()
    |> Enum.each(fn booking ->
      case BookingLocker.release_hold(booking.id) do
        {:ok, _updated_booking} ->
          Logger.info("Expired booking hold due to timeout",
            booking_id: booking.id,
            reference_id: booking.reference_id,
            user_id: booking.user_id,
            property: booking.property,
            booking_mode: booking.booking_mode
          )

        {:error, reason} ->
          Logger.error("Failed to expire booking hold",
            booking_id: booking.id,
            reference_id: booking.reference_id,
            user_id: booking.user_id,
            error: reason
          )
      end
    end)
  end

  @impl Oban.Worker
  def timeout(_job) do
    # Job timeout after 60 seconds (may need to process multiple bookings)
    60_000
  end
end
