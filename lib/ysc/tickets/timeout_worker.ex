defmodule Ysc.Tickets.TimeoutWorker do
  @moduledoc """
  Background worker for handling ticket order timeouts.

  This worker runs periodically to:
  - Find ticket orders that have exceeded the 30-minute payment timeout
  - Expire those orders and release the reserved tickets
  - Clean up expired orders
  """

  use Oban.Worker, queue: :tickets, max_attempts: 3

  import Ecto.Query
  require Logger

  alias Ysc.Tickets

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action" => "schedule_next"}}) do
    # This job schedules the next timeout check and then schedules itself again
    expire_timed_out_orders()
    Ysc.Tickets.Scheduler.schedule_next_timeout_check()
    {:ok, "Expired timed out ticket orders and scheduled next check"}
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ticket_order_id" => ticket_order_id}}) do
    # Handle individual order timeout
    expire_specific_order(ticket_order_id)
    {:ok, "Expired specific ticket order"}
  end

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    expire_timed_out_orders()
    {:ok, "Expired timed out ticket orders"}
  end

  @doc """
  Expires a specific ticket order by ID.
  """
  def expire_specific_order(ticket_order_id) do
    case Ysc.Repo.get(Ysc.Tickets.TicketOrder, ticket_order_id) do
      nil ->
        Logger.warning("Ticket order not found for expiration", ticket_order_id: ticket_order_id)
        :ok

      ticket_order ->
        if ticket_order.status == :pending do
          case Tickets.expire_ticket_order(ticket_order) do
            {:ok, _expired_order} ->
              Logger.info("Expired specific ticket order due to timeout",
                ticket_order_id: ticket_order.id,
                reference_id: ticket_order.reference_id,
                user_id: ticket_order.user_id
              )

            {:error, reason} ->
              Logger.error("Failed to expire specific ticket order",
                ticket_order_id: ticket_order.id,
                reference_id: ticket_order.reference_id,
                error: reason
              )
          end
        else
          Logger.info("Ticket order already processed, skipping expiration",
            ticket_order_id: ticket_order.id,
            status: ticket_order.status
          )
        end
    end
  end

  @doc """
  Manually trigger expiration of timed out orders.
  This can be called from a cron job or scheduled task.
  """
  def expire_timed_out_orders do
    timeout_threshold = DateTime.add(DateTime.utc_now(), -30, :minute)

    Ysc.Tickets.TicketOrder
    |> where([t], t.status == :pending and t.expires_at < ^timeout_threshold)
    |> preload(:tickets)
    |> Ysc.Repo.all()
    |> Enum.each(fn ticket_order ->
      case Tickets.expire_ticket_order(ticket_order) do
        {:ok, _expired_order} ->
          Logger.info("Expired ticket order due to timeout",
            ticket_order_id: ticket_order.id,
            reference_id: ticket_order.reference_id,
            user_id: ticket_order.user_id
          )

        {:error, reason} ->
          Logger.error("Failed to expire ticket order",
            ticket_order_id: ticket_order.id,
            reference_id: ticket_order.reference_id,
            error: reason
          )
      end
    end)
  end

  @doc """
  Schedules a timeout check job to run every 5 minutes.
  """
  def schedule_timeout_check do
    %{}
    |> new()
    |> Oban.insert()
  end

  @doc """
  Schedules a one-time timeout check for a specific ticket order.
  """
  def schedule_order_timeout(ticket_order_id, expires_at) do
    # Calculate delay until expiration
    delay_seconds = DateTime.diff(expires_at, DateTime.utc_now(), :second)

    if delay_seconds > 0 do
      %{ticket_order_id: ticket_order_id}
      |> new(schedule_in: delay_seconds)
      |> Oban.insert()
    end
  end

  @impl Oban.Worker
  def timeout(_job) do
    # Job timeout after 30 seconds
    30_000
  end
end
