defmodule Ysc.TestLoggerBackend do
  @moduledoc """
  Custom logger backend for tests that filters out expected test errors.
  This reduces log noise from expected error scenarios during test runs.
  """

  @behaviour GenEvent

  # Patterns that indicate expected test errors (these are tested scenarios)
  @expected_error_patterns [
    "Mox.UnexpectedCallError",
    "DBConnection.ConnectionError",
    "Postgrex.Protocol",
    "Mint.TransportError",
    "Failed to subscribe email to Mailpoet",
    "MailpoetSubscriber: Failed to subscribe",
    "Failed to process ticket order payment",
    "Failed to cancel ticket order",
    "no_ticket_order_metadata",
    "Failed to enqueue QuickBooks sync",
    "Failed to fetch BillPayment from QuickBooks",
    "Failed to retrieve payment intent for refund",
    "No such payment_intent",
    "SMS not scheduled",
    "Template module not found",
    "Failed to send Discord alert",
    "unknown registry: YscWeb.Finch",
    "Image not found",
    "LEDGER IMBALANCE DETECTED",
    "Ledger imbalance details",
    "Account balance",
    "CRITICAL: Ledger imbalance detected",
    "Reconciliation found discrepancies",
    "BookingLocker.atomic_booking failed",
    "Expense report not found for QuickBooks sync",
    "Invalid inbound SMS webhook payload",
    "Invalid delivery receipt webhook payload",
    "Webhook event not found",
    "Webhook event processing failed",
    "Failed to sync payment to QuickBooks",
    "Sync failed in pipeline",
    "Token refresh failed",
    "EmailNotifier job failed",
    "Unknown reminder type",
    "Failed to create SMS received record",
    "Failed to cancel PaymentIntent"
  ]

  def init(_) do
    {:ok, %{}}
  end

  def handle_event({level, _gl, {Logger, msg, _ts, md}}, state) when level == :error do
    message_str = to_string(msg)
    # Also check metadata for error messages
    metadata_str = inspect(md)
    full_message = message_str <> " " <> metadata_str

    # Check if this is an expected test error - if so, completely suppress it
    is_expected_error =
      Enum.any?(@expected_error_patterns, fn pattern ->
        String.contains?(message_str, pattern) || String.contains?(full_message, pattern)
      end)

    # Only log if it's not an expected test error
    unless is_expected_error do
      # Use minimal format for unexpected errors
      IO.puts(:stderr, "\n[ERROR] #{message_str}\n")
    end

    {:ok, state}
  end

  def handle_event({_level, _gl, {Logger, _msg, _ts, _md}}, state) do
    # Don't log non-error messages (they should be filtered by level anyway)
    {:ok, state}
  end

  def handle_event(_, state) do
    {:ok, state}
  end

  def handle_call({:configure, _opts}, state) do
    {:ok, :ok, state}
  end

  def handle_info(_, state) do
    {:ok, state}
  end

  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  def terminate(_reason, _state) do
    :ok
  end
end
